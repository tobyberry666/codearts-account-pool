package auth

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestAnonymousAccountsRemainSeparate(t *testing.T) {
	dir := t.TempDir()
	first := New("", "first", "", "token-a", "ak", "sk", "", "", "")
	second := New("", "second", "", "token-b", "ak", "sk", "", "", "")
	for _, a := range []*Auth{first, second} {
		if err := SaveNew(dir, a); err != nil {
			t.Fatal(err)
		}
	}
	loaded, err := LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 2 {
		t.Fatalf("got %d accounts, want 2", len(loaded))
	}
	name := first.FileName()
	if name == second.FileName() {
		t.Fatal("logins share a credential file")
	}
	if err := first.UpdateCredentials("refreshed", "ak", "sk", "", ""); err != nil {
		t.Fatal(err)
	}
	if first.FileName() != name {
		t.Fatal("identity changed during refresh")
	}
}

func TestLegacyAnonymousAccountGetsPersistentIdentity(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "codearts-unknown.json")
	if err := os.WriteFile(path, []byte(`{"user_id":"","cloud_dragon_token":"existing"}`), 0600); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var saved map[string]any
	raw, _ := os.ReadFile(path)
	if err := json.Unmarshal(raw, &saved); err != nil {
		t.Fatal(err)
	}
	if saved["account_id"] == nil || saved["account_id"] == "" {
		t.Fatal("missing persistent account ID")
	}
	again, err := LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if loaded[0].FileName() != again[0].FileName() || again[0].Token() != "existing" {
		t.Fatal("migration changed login or identity")
	}
}
