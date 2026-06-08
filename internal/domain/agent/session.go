package agent

type Session struct {
	Branch  string `json:"branch"`
	Editor  string `json:"editor"`
	PID     int    `json:"pid"`
	Command string `json:"command"`
}
