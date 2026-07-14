package agent

type Session struct {
	Branch  string `json:"branch"`
	Editor  string `json:"editor"`
	PID     int    `json:"pid"`
	Command string `json:"command"`
	Path    string `json:"path"`
	Tab     string `json:"tab"`
	PaneID  int    `json:"pane_id"`
}
