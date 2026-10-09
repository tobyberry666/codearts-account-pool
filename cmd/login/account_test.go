package main

import (
	"codearts2api/internal/auth"
	"os"
	"path/filepath"
	"testing"
)

func TestReloginPreservesLegacyFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "codearts-unknown.json")
	os.WriteFile(path, []byte(`{"account_id":"local-first","cloud_dragon_token":"old"}`), 0600)
	a := auth.New("cloud-user", "", "", "new", "", "", "", "", "")
	if err := saveLoginAuth(dir, "local-first", path, a); err != nil {
		t.Fatal(err)
	}
	loaded, err := auth.LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 1 || loaded[0].ID() != "local-first" || loaded[0].Token() != "new" {
		t.Fatal("re-login did not replace selected account")
	}
}

func TestReloginRejectsOutsideOrMismatchedAccount(t *testing.T) {
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "codearts-other.json")
	if err := validateRelogin(dir, "local-first", outside); err == nil {
		t.Fatal("accepted outside file")
	}
	path := filepath.Join(dir, "codearts-one.json")
	os.WriteFile(path, []byte(`{"account_id":"local-first","cloud_dragon_token":"old"}`), 0600)
	if err := validateRelogin(dir, "local-other", path); err == nil {
		t.Fatal("accepted mismatched identity")
	}
}

func TestSameCloudAccountDoesNotCreateDuplicate(t *testing.T) {
	dir := t.TempDir()
	a := auth.New("known-user", "", "", "old", "", "", "", "", "")
	a.SetAccountID("local-existing")
	if err := auth.SaveNew(dir, a); err != nil {
		t.Fatal(err)
	}
	b := auth.New("known-user", "", "", "new", "", "", "", "", "")
	if err := saveLoginAuth(dir, "", "", b); err != nil {
		t.Fatal(err)
	}
	loaded, err := auth.LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 1 || loaded[0].ID() != "local-existing" {
		t.Fatal("duplicate cloud account was added")
	}
}

func TestReloginCannotDuplicateAnotherKnownAccount(t *testing.T) {
	dir := t.TempDir()
	known := auth.New("cloud-known", "", "", "known", "", "", "", "", "")
	if err := auth.SaveNew(dir, known); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "codearts-unknown.json")
	os.WriteFile(path, []byte(`{"account_id":"local-legacy","cloud_dragon_token":"legacy"}`), 0600)
	duplicate := auth.New("cloud-known", "", "", "new", "", "", "", "", "")
	if err := saveLoginAuth(dir, "local-legacy", path, duplicate); err == nil {
		t.Fatal("re-login created a duplicate known cloud account")
	}
	loaded, err := auth.LoadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range loaded {
		if a.ID() == "local-legacy" && a.Token() != "legacy" {
			t.Fatal("rejected login changed original credentials")
		}
	}
}
