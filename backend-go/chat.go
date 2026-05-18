package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"github.com/gorilla/websocket"
)

var upgraderWS = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool { return true }, // allow all devices to connect
}

// keep track of all active device connections
var chatRoomsPool = make(map[string]map[*websocket.Conn]bool)
var broadcast = make(chan []byte)
var poolMutex sync.Mutex

func HandleWebSockets(w http.ResponseWriter, r *http.Request) {
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