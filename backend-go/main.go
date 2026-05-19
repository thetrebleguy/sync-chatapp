package main

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

type User struct {
	ID					string `json:"user_id"`
	UserName 			string `json:"user_name"`
	Email				string `json:"email"`
	PasswordHash		string `json:"-"`
	PhoneNumber     	string `json:"phone_number"`
	Role				string `json:"role"`
	CurrentCompany		string `json:"current_company"`
	Specialization		string `json:"specialization"`
}

type CVSubmission struct {
    UserID    string `json:"user_id"`
    ExpertID  string `json:"expert_id"`
    FileURL   string `json:"file_url"`
    Status    string `json:"status"`
}

type ChatRoomRequest struct {
	StudentID string `json:"student_id"`
	ExpertID  string `json:"expert_id"`
}

type MessageRequest struct {
	RoomID      string `json:"room_id"`
	SenderID    string `json:"sender_id"`
	Content     string `json:"content"`
	MessageType string `json:"message_type"`
}

func CORSMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // allows phone/emulator to talk to the server
        c.Writer.Header().Set("Access-Control-Allow-Origin", "*") 
        c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
        c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
        c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT")

        // check handling
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }

        c.Next()
    }
}

var db *sql.DB

func main(){
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: No .env file found. Falling back to system environment variables.")
	}

	connStr := os.Getenv("DB_CONN_STR")
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	if err = db.Ping(); err != nil {
		log.Fatal("Database unreachable:", err)
	}

	// setup routes
	r := gin.Default()
	r.Use(CORSMiddleware())

	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "Backend is up"})
	})

	// WEBSOCKET
	r.GET("/ws", func(c *gin.Context) {
		HandleWebSockets(c.Writer, c.Request)
	})

	// POST: Register and Login
	r.GET("/profile/:id", GetUserProfile)
	r.POST("/register", RegisterUser)
	r.POST("/login", LoginUser)
	r.POST("/submit-cv", SubmitCV)
	r.POST("/upload", UploadToStorage)

	// POST: chat system
	r.POST("/chat-rooms", CreateChatRoom)
	r.POST("/messages", SaveMessage)

	// GET: Experts
	r.GET("/experts", GetExperts)
	r.GET("/expert-rooms/:expert_id", GetExpertChatRooms)
	r.GET("/chat-history/:room_id", GetChatHistory)


	// 4. Start Server
	r.Run(":8080")
}