package review

type PullRequest struct {
	Branch       string   `json:"branch"`
	Number       int      `json:"number"`
	URL          string   `json:"url"`
	State        string   `json:"state"`
	Draft        bool     `json:"draft"`
	Checks       string   `json:"checks"`
	CheckDetails []string `json:"check_details,omitempty"`
}
