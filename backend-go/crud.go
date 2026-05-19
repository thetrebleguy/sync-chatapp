package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"
	
	"golang.org/x/crypto/bcrypt"
	"github.com/gin-gonic/gin"
)


// REGISTER USER
func RegisterUser (c *gin.Context) {
	var input struct {
		UserName		string `json:"user_name"`
		Email			string `json:"email"`
		Password		string `json:"password"`
		PhoneNumber		string `json:"phone_number"`
		Role			string `json:"role"`
		CurrentCompany 	string `json:"current_company"`
		Specialization 	string `json:"specialization"`
	}

	// parse the json
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	
	// hash the password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	// insert into the supabase
	query := `INSERT INTO users (user_name, email, password_hash, phone_number, role, current_company, specialization) 
              VALUES ($1, $2, $3, $4, $5, $6, $7) 
              RETURNING user_id`
    
    // create a variable to hold the new ID
    var newID string

    // use QueryRow instead of Exec so we can .Scan() the ID into our variable
    err = db.QueryRow(query, 
        input.UserName, 
        input.Email, 
        string(hashedPassword), 
        input.PhoneNumber, 
        input.Role, 
        input.CurrentCompany, 
        input.Specialization,
    ).Scan(&newID)

    if err != nil {
        fmt.Println("DATABASE ERROR:", err) 
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    // now use that newID variable in your response
    c.JSON(201, gin.H{
        "message": "User created successfully",
        "user_id": newID, 
    })
}

// LOGIN
func LoginUser (c *gin.Context) {
	var loginReq struct {
		Email		string `json:"email"`
		Password	string `json:"password"`
	}

	if err := c.ShouldBindJSON(&loginReq); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var storedHash string
	var userID string
	query := `SELECT user_id, password_hash FROM users WHERE email = $1`
	err := db.QueryRow(query, loginReq.Email).Scan(&userID, &storedHash)

	// if email invalid
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
        return
    }

	// if password invalid
	err = bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(loginReq.Password))
    if err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
        return
    }

	// success!
	c.JSON(http.StatusOK, gin.H{
        "message": "Login successful!",
        "user_id": userID,
    })
}

func GetUserProfile (c *gin.Context) {
	 id := c.Param("id") 
    var name, role, spec, company string
	
	err := db.QueryRow("SELECT user_name, role, specialization, current_company FROM users WHERE user_id = $1::uuid", id).
    	Scan(&name, &role, &spec, &company)

	if err != nil {
        c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "user_name":      name,
        "role":           role,
        "specialization": spec,
        "company":        company,
    })
}

// SUBMIT CV
func SubmitCV (c *gin.Context) {
	var req struct {
        StudentID string `json:"student_id"`
        ExpertID  string `json:"expert_id"`
        FileURL   string `json:"file_url"`
    }

	if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid data format"})
        return
    }

	var lastInsertID string
	query := `INSERT INTO review_request (student_id, expert_id, file_url, status) 
			VALUES ($1, $2, $3, 'pending') RETURNING id`
	err := db.QueryRow(query, req.StudentID, req.ExpertID, req.FileURL).Scan(&lastInsertID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save submission"})
        return
    }

	c.JSON(http.StatusOK, gin.H{
        "message": "CV submitted successfully for review!",
        "status":  "pending",
    })
}

// GET EXPERT
func GetExperts (c *gin.Context) {
	rows, err := db.Query("SELECT user_id, user_name, current_company, specialization FROM users WHERE role = 'expert'")
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
	}
	defer rows.Close()

	var experts []map[string]interface{}
    for rows.Next() {
        var id, name, company, spec string
        rows.Scan(&id, &name, &company, &spec)
        experts = append(experts, map[string]interface{}{
            "id":              id,
            "name":            name,
            "current_company": company,
            "specialization":  spec,
        })
    }

	c.JSON(http.StatusOK, experts)
}

// UPLOAD TO STORAGE
func UploadToStorage(c *gin.Context) {
	header, err := c.FormFile("file")

	if (err != nil) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file received"})
		return
	}

	// explicitly open the file from the header to read its binary data
	file, err := header.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to open received file"})
		return
	}
	defer file.Close()

	// ensure only pdf format
	if filepath.Ext(header.Filename) != ".pdf" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only PDF files are allowed"})
		return
	}

	buf := bytes.NewBuffer(nil)
	if _, err := io.Copy(buf, file); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to parse file content"})
		return
	}

	// generate a unique file name
	uniqueFilename := fmt.Sprintf("%d_%s", time.Now().UnixNano(), header.Filename)
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_KEY")
	uploadURL := fmt.Sprintf("%s/storage/v1/object/resumes/%s", supabaseURL, uniqueFilename)

	// request to post
	req, err := http.NewRequest("POST", uploadURL, buf)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to formulate upstream request"})
		return
	}

	req.Header.Set("Authorization", "Bearer "+supabaseKey)
	req.Header.Set("ApiKey", supabaseKey)
	req.Header.Set("Content-Type", "application/pdf")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Supabase connection refused"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := io.ReadAll(resp.Body)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":  "Supabase Storage engine error response",
			"detail": string(bodyBytes),
		})
		return
	}

	// accessible public download link
	publicURL := fmt.Sprintf("%s/storage/v1/object/resumes/%s", supabaseURL, uniqueFilename)

	c.JSON(http.StatusOK, gin.H{
		"message":  "File uploaded to cloud bucket successfully!",
		"file_url": publicURL,
	})
}

func CreateChatRoom (c *gin.Context) {
	var req ChatRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request parameters"})
		return
	}

	var RoomID string
	checkQuery := `SELECT room_id FROM chat_rooms WHERE (student_id = $1 AND expert_id = $2) OR (student_id = $2 AND expert_id = $1) LIMIT 1`
	err := db.QueryRow(checkQuery, req.StudentID, req.ExpertID).Scan(&RoomID)
	if err == nil {
		c.JSON(http.StatusOK, gin.H{"room_id": RoomID, "message": "Existing chat room retrieved"})
		return
	}

	insertQuery := `INSERT INTO chat_rooms (student_id, expert_id) VALUES ($1, $2) RETURNING room_id`
	err = db.QueryRow(insertQuery, req.StudentID, req.ExpertID).Scan(&RoomID)

	if err != nil {
		fmt.Println("DEBUG: Create ChatRoom SQL Error ->", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to establish chat room"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"room_id": RoomID, "message": "Chat room created successfully"})
}

func GetExpertChatRooms(c *gin.Context) {
	expertID := c.Param("expert_id")

	// Query to grab rooms and fetch the corresponding student names
	query := `
		SELECT cr.room_id, cr.student_id, u.user_name 
		FROM chat_rooms cr
		JOIN users u ON cr.student_id = u.user_id
		WHERE cr.expert_id = $1::uuid
	`

	rows, err := db.Query(query, expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch chat rooms: " + err.Error()})
		return
	}
	defer rows.Close()

	var rooms []map[string]interface{}
	for rows.Next() {
		var roomID, studentID, studentName string
		if err := rows.Scan(&roomID, &studentID, &studentName); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error scanning room data"})
			return
		}

		rooms = append(rooms, map[string]interface{}{
			"room_id":      roomID,
			"student_id":   studentID,
			"student_name": studentName,
		})
	}

	// Fallback to empty array instead of null if no rooms exist yet
	if rooms == nil {
		rooms = []map[string]interface{}{}
	}

	c.JSON(http.StatusOK, rooms)
}

func SaveMessage(c *gin.Context) {
	var req MessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request parameters"})
		return
	}

	if req.MessageType == "" {
		req.MessageType = "text"
	}

	var messageID string
	var sentAt string
	query := `INSERT INTO messages (room_id, sender_id, content, message_type) VALUES ($1, $2, $3, $4) RETURNING message_id, sent_at`
	err := db.QueryRow(query, req.RoomID, req.SenderID, req.Content, req.MessageType).Scan(&messageID, &sentAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to record message to database"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message_id": messageID, "room_id": req.RoomID, "sender_id": req.SenderID, "content": req.Content, "message_type": req.MessageType, "sent_at": sentAt})
}

func GetChatHistory(c *gin.Context) {
	roomID := c.Param("room_id")

	query := `
		SELECT room_id, sender_id, content, sent_at 
		FROM messages 
		WHERE room_id = $1::uuid 
		ORDER BY sent_at ASC
	`

	rows, err := db.Query(query, roomID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read history: " + err.Error()})
		return
	}
	defer rows.Close()

	var history []map[string]interface{}
	for rows.Next() {
		var rID, senderID, content string
		var sentAt time.Time
		if err := rows.Scan(&rID, &senderID, &content, &sentAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Error parsing message row"})
			return
		}

		history = append(history, map[string]interface{}{
			"room_id":   rID,
			"sender_id": senderID,
			"content":   content,
			"sent_at":   sentAt,
		})
	}

	if history == nil {
		history = []map[string]interface{}{}
	}

	c.JSON(http.StatusOK, history)
}