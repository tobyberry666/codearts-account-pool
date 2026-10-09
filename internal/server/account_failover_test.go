package server

import (
	"codearts2api/internal/auth"
	"codearts2api/internal/pool"
	"codearts2api/internal/upstream"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func failoverPool(t *testing.T, count int) (*pool.Pool, []*atomic.Int32, []*atomic.Int32) {
	t.Helper()
	auths := make([]*auth.Auth, count)
	calls, modes := make([]*atomic.Int32, count), make([]*atomic.Int32, count)
	for i := range auths {
		auths[i] = auth.New(fmt.Sprintf("%s-%d", t.Name(), i), "tester", "", "token", "ak", "sk", time.Now().Add(time.Hour).Format(time.RFC3339), "", "")
		calls[i], modes[i] = &atomic.Int32{}, &atomic.Int32{}
	}
	p, err := pool.New(auths, pool.Config{MaxConcurrent: 1}, "")
	if err != nil {
		t.Fatal(err)
	}
	for i, a := range p.Accounts() {
		call, mode := calls[i], modes[i]
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			call.Add(1)
			switch mode.Load() {
			case 429:
				w.WriteHeader(429)
				io.WriteString(w, `{"error_msg":"TPM limit exceeded"}`)
			case 400:
				w.WriteHeader(400)
				io.WriteString(w, `{"error_code":"TM.00001041","error_msg":"并发会话数已达上限"}`)
			case 404:
				w.WriteHeader(400)
				io.WriteString(w, `{"error_msg":"model not registered"}`)
			case 401:
				w.WriteHeader(401)
				io.WriteString(w, `{"error_msg":"unauthorized"}`)
			default:
				w.Header().Set("Content-Type", "text/event-stream")
				io.WriteString(w, "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
			}
		}))
		t.Cleanup(srv.Close)
		a.Client = upstream.NewWithChatEndpoint(time.Second, srv.URL)
	}
	return p, calls, modes
}

func failoverRequest(h *Handler) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "/v1/chat/completions", strings.NewReader(`{"model":"glm-5.2","conversation_id":"0123456789abcdef0123456789abcdef","messages":[{"role":"user","content":"test"}]}`))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestFailoverKeepsNewAccountSticky(t *testing.T) {
	for _, mode := range []int32{429, 400, 404, 401} {
		t.Run(fmt.Sprint(mode), func(t *testing.T) {
			p, calls, modes := failoverPool(t, 2)
			cfg := Config{Pool: p, MaxRotate: 1, QueueMaxAttempts: 2, QueueRetryDelay: time.Millisecond, ConvStateFile: filepath.Join(t.TempDir(), "chats.json")}
			h := NewHandler(cfg)
			if w := failoverRequest(h); w.Code != 200 {
				t.Fatalf("initial %d %s", w.Code, w.Body)
			}
			modes[0].Store(mode)
			if w := failoverRequest(h); w.Code != 200 {
				t.Fatalf("failover %d %s", w.Code, w.Body)
			}
			if calls[0].Load() != 2 || calls[1].Load() != 1 {
				t.Fatalf("calls %d/%d", calls[0].Load(), calls[1].Load())
			}
			modes[0].Store(0)
			p.Enable(p.Accounts()[0].Name)
			p.ClearCooldown(p.Accounts()[0].Name)
			h = NewHandler(cfg)
			if w := failoverRequest(h); w.Code != 200 {
				t.Fatalf("restart %d %s", w.Code, w.Body)
			}
			if calls[0].Load() != 2 || calls[1].Load() != 2 {
				t.Fatalf("lost successful affinity after restart: %d/%d", calls[0].Load(), calls[1].Load())
			}
		})
	}
}

func TestFailoverAttemptsAllConfiguredAccounts(t *testing.T) {
	p, calls, modes := failoverPool(t, 4)
	for _, m := range modes[:3] {
		m.Store(429)
	}
	h := NewHandler(Config{Pool: p, MaxRotate: 1, QueueMaxAttempts: 1})
	if w := failoverRequest(h); w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	for i, c := range calls {
		if c.Load() != 1 {
			t.Fatalf("account %d calls=%d", i, c.Load())
		}
	}
}

func TestAllAccountsCoolingDoNotSendMoreRequests(t *testing.T) {
	p, calls, modes := failoverPool(t, 3)
	for _, m := range modes {
		m.Store(429)
	}
	h := NewHandler(Config{Pool: p, QueueMaxAttempts: 1})
	for i := 0; i < 2; i++ {
		w := failoverRequest(h)
		if w.Code != 429 || w.Header().Get("Retry-After") == "" {
			t.Fatalf("%d %s", w.Code, w.Body)
		}
	}
	for i, c := range calls {
		if c.Load() != 1 {
			t.Fatalf("account %d retried while cooling: %d", i, c.Load())
		}
	}
}

func TestBusyStickyAccountUsesIdleBackup(t *testing.T) {
	p, calls, _ := failoverPool(t, 2)
	h := NewHandler(Config{Pool: p})
	if w := failoverRequest(h); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if !p.TryAcquire(p.Accounts()[0].Name) {
		t.Fatal("could not occupy sticky account")
	}
	defer p.ReleaseLock(p.Accounts()[0].Name)
	if w := failoverRequest(h); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if calls[0].Load() != 1 || calls[1].Load() != 1 {
		t.Fatal("idle backup was not used")
	}
}

func TestExpiredAccountWithoutRefreshUsesBackup(t *testing.T) {
	p, calls, _ := failoverPool(t, 2)
	p.Accounts()[0].Auth.Expiration = time.Now().Add(-time.Hour).Format(time.RFC3339)
	h := NewHandler(Config{Pool: p})
	if w := failoverRequest(h); w.Code != 200 {
		t.Fatal(w.Body)
	}
	if calls[0].Load() != 0 || calls[1].Load() != 1 {
		t.Fatal("expired credential was sent upstream")
	}
}

func TestStreamingFailureDoesNotReplayOnBackup(t *testing.T) {
	p, calls, _ := failoverPool(t, 2)
	first := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		io.WriteString(w, "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")
		w.(http.Flusher).Flush()
		io.WriteString(w, "event: done\ndata: {\"error_code\":\"failed\",\"error_msg\":\"failed\"}\n\n")
	}))
	defer first.Close()
	p.Accounts()[0].Client = upstream.NewWithChatEndpoint(time.Second, first.URL)
	h := NewHandler(Config{Pool: p})
	r := httptest.NewRequest("POST", "/v1/chat/completions", strings.NewReader(`{"model":"glm-5.2","stream":true,"messages":[{"role":"user","content":"test"}]}`))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if !strings.Contains(w.Body.String(), "partial") || calls[1].Load() != 0 {
		t.Fatal("partially streamed answer was replayed on another account")
	}
}

func TestConcurrentLimitDoesNotSpinSingleAccount(t *testing.T) {
	p, calls, modes := failoverPool(t, 1)
	modes[0].Store(400)
	h := NewHandler(Config{Pool: p, QueueMaxAttempts: 3, QueueRetryDelay: time.Millisecond})
	w := failoverRequest(h)
	if w.Code != 429 || calls[0].Load() != 1 {
		t.Fatalf("status %d, calls %d", w.Code, calls[0].Load())
	}
	if p.List()[0]["active_concurrent"] != 0 {
		t.Fatal("request slot not released")
	}
}
