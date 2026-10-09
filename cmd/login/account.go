package main

import (
	"codearts2api/internal/auth"
	"codearts2api/internal/upstream"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func validateRelogin(dir, id, path string) error {
	if id == "" && path == "" {
		return nil
	}
	if id == "" || path == "" {
		return fmt.Errorf("account-id and auth-file must be provided together")
	}
	root, err := filepath.Abs(dir)
	if err != nil {
		return err
	}
	file, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	if !strings.EqualFold(filepath.Dir(file), root) || !strings.HasPrefix(filepath.Base(file), "codearts-") || !strings.HasSuffix(file, ".json") {
		return fmt.Errorf("auth-file must be a credential file directly inside auth-dir")
	}
	info, err := os.Lstat(file)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("auth-file must be a regular file")
	}
	raw, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	var existing auth.Auth
	if err = json.Unmarshal(raw, &existing); err != nil {
		return err
	}
	if existing.ID() != id {
		return fmt.Errorf("selected account identity does not match auth-file")
	}
	return nil
}

func saveLoginAuth(dir, id, path string, a *auth.Auth) error {
	if err := validateRelogin(dir, id, path); err != nil {
		return err
	}
	if path != "" {
		loaded, err := auth.LoadDir(dir)
		if err != nil {
			return err
		}
		for _, other := range loaded {
			if other.ID() != id && a.UserID != "" && other.UserID == a.UserID {
				return fmt.Errorf("this cloud account is already saved; re-login its existing entry instead")
			}
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		var existing auth.Auth
		if err = json.Unmarshal(raw, &existing); err != nil {
			return err
		}
		if existing.UserID != "" && a.UserID != "" && existing.UserID != a.UserID {
			return fmt.Errorf("logged in to a different cloud account; use Add account instead")
		}
		a.SetAccountID(id)
		return a.SetPathAndSave(path)
	}
	loaded, err := auth.LoadDir(dir)
	if err != nil {
		return err
	}
	for _, existing := range loaded {
		if a.UserID != "" && existing.UserID == a.UserID {
			a.SetAccountID(existing.ID())
			return a.SetPathAndSave(existing.Path())
		}
	}
	return auth.SaveNew(dir, a)
}

func resolveLoginIdentity(a *auth.Auth) {
	if a.UserID != "" {
		return
	}
	token, ak, sk := a.Credentials()
	cred := upstream.SignCredential{SecurityToken: token, AccessKeyID: ak, SecretAccessKey: sk}
	uid, name, domain, err := upstream.CallerIdentity(cred)
	if err != nil || uid == "" {
		uid, name, domain, err = upstream.CurrentUser(cred)
	}
	if err == nil && uid != "" {
		a.UserID = uid
		a.UserName = name
		a.DomainID = domain
	}
}
