package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"context"
	"log"
	"os"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
	"github.com/gorilla/websocket"
)

var upgraderWS = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool { return true }, // allow all devices to connect
}

// keep track of all active device connections
var chatRoomsPool = make(map[string]map[*websocket.Conn]bool)
var broadcast = make(chan []byte)
var poolMutex sync.Mutex

var fcmClient *messaging.Client

func initFirebase() {
	opt := option.WithCredentialsFile("serviceAccountKey.json")
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		log.Fatalf("Error initializing Firebase App: %v", err)
	}

	client, err := app.Messaging(context.Background())
	if err != nil {
		log.Fatalf("Error initializing Firebase Messaging client: %v", err)
	}
	fcmClient = client
	fmt.Println("Firebase Admin SDK initialized successfully!")
}

func HandleWebSockets(w http.ResponseWriter, r *http.Request) {
	if fcmClient == nil {
		initFirebase()
	}

	roomID := r.URL.Query().Get("room_id")
	if roomID == "" {
		return 
	}

	conn, err := upgraderWS.Upgrade(w, r, nil)
    if err != nil {
        return
    }
    defer conn.Close()

	poolMutex.Lock()
	if chatRoomsPool[roomID] == nil {
		chatRoomsPool[roomID] = make(map[*websocket.Conn]bool)
	}
	chatRoomsPool[roomID][conn] = true
	poolMutex.Unlock()

	for {
		_, msgBytes, err := conn.ReadMessage()
		if err != nil {
			poolMutex.Lock()
			delete(chatRoomsPool[roomID], conn)
			poolMutex.Unlock()
			break
		}

		var data MessageRequest
		if err := json.Unmarshal(msgBytes, &data); err == nil {
			if data.RoomID != "" && data.SenderID != "" && data.Content != "" {
				go func(req MessageRequest) {
					query := `INSERT INTO messages (room_id, sender_id, content, message_type) 
					          VALUES ($1, $2, $3, 'text')`
					_, err := db.Exec(query, req.RoomID, req.SenderID, req.Content)
					if err != nil {
						fmt.Println("DB Asynchronous Background Save Error:", err)
					}

					targetDeviceToken := os.Getenv("TARGET_DEVICE_TOKEN")

					if targetDeviceToken == "" {
						fmt.Println("Warning: TARGET_DEVICE_TOKEN is empty in environment variables")
						return
					}
					
					msgPayload := &messaging.Message{
						Token: targetDeviceToken,
						Notification: &messaging.Notification{
							Title: "New Message Received",
							Body:  req.Content,
						},
						Data: map[string]string{
							"room_id": req.RoomID,
						},
					}

					response, err := fcmClient.Send(context.Background(), msgPayload)
					if err != nil {
						fmt.Printf("FCM Error pushing notification: %v\n", err)
					} else {
						fmt.Printf("Successfully sent cloud push message response!", response)
					}

					// 3. Broadcast to all active websockets in the room
					poolMutex.Lock()
					for clientConn := range chatRoomsPool[req.RoomID] {
						err := clientConn.WriteMessage(websocket.TextMessage, msgBytes)
						if err != nil {
							clientConn.Close()
							delete(chatRoomsPool[req.RoomID], clientConn)
						}
					}
					poolMutex.Unlock()
				}(data)
			}
		}

		poolMutex.Lock()
		for client := range chatRoomsPool[roomID] {
			err := client.WriteMessage(websocket.TextMessage, msgBytes)
			if err != nil {
				client.Close()
				delete(chatRoomsPool[roomID], client)
			}
		}
		poolMutex.Unlock()
	}
}