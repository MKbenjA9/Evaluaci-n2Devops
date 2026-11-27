package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestDockerAccessPolicy(t *testing.T) {
	for _, test := range []struct {
		method string
		target string
		status int
	}{
		{"HEAD", "/_ping", 200},
		{"GET", "/version", 200},
		{"HEAD", "/version", 403},
		{"GET", "/v1.52/containers/order-manager-api/json", 200},
		{"GET", "/containers/order-manager-db/logs?stdout=1&stderr=1&follow=1&timestamps=1&since=0", 200},
		{"POST", "/containers/order-manager-api/logs", 403},
		{"DELETE", "/containers/order-manager-db/json", 403},
		{"GET", "/containers/json", 403},
		{"GET", "/containers/order-manager-api/archive", 403},
		{"GET", "/containers/other/logs", 403},
		{"GET", "/containers/abcdef123456/logs", 403},
		{"GET", "/containers/ORDER-MANAGER-API/logs", 403},
		{"GET", "/containers/%6frder-manager-api/logs", 403},
		{"GET", "/containers/order-manager-api%2Flogs", 403},
		{"GET", "/containers/order-manager-api/../order-manager-db/logs", 403},
		{"GET", "/containers//order-manager-api/logs", 403},
		{"GET", "/containers/order-manager-api/logs/", 403},
		{"GET", "/v1.bad/containers/order-manager-api/logs", 403},
		{"GET", "http://different-host/containers/order-manager-api/logs", 403},
		{"GET", "/containers/order-manager-api/logs?details=1", 403},
		{"GET", "/containers/order-manager-api/logs?stdout=1&stdout=0", 403},
		{"GET", "/containers/order-manager-api/logs?stdout=1&%73tdout=0", 403},
		{"GET", "/containers/order-manager-api/logs?stdout=1;details=1", 403},
		{"GET", "/containers/order-manager-api/logs?since=-1", 403},
		{"GET", "/containers/order-manager-api/logs?tail=all", 403},
		{"GET", "/containers/order-manager-api/json?size=1", 403},
		{"GET", "/containers/order-manager-api/json?", 403},
	} {
		t.Run(test.method+" "+test.target, func(t *testing.T) {
			calls := 0
			handler := dockerLogsHandler(roundTripFunc(func(r *http.Request) (*http.Response, error) {
				calls++
				if r.Header.Get("X-HTTP-Method-Override") != "" {
					t.Error("forwarded method override header")
				}
				return &http.Response{StatusCode: 200, Header: make(http.Header), Request: r,
					Body: io.NopCloser(strings.NewReader("{}"))}, nil
			}))
			req := httptest.NewRequest(test.method, test.target, nil)
			req.Header.Set("X-HTTP-Method-Override", "DELETE")
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			if rec.Code != test.status || (calls == 1) != (test.status == 200) {
				t.Fatalf("status %d, upstream calls %d", rec.Code, calls)
			}
		})
	}
}

func TestUnexpectedBodyAndUpgradeAreDenied(t *testing.T) {
	handler := dockerLogsHandler(roundTripFunc(func(*http.Request) (*http.Response, error) {
		t.Fatal("unexpected upstream request")
		return nil, nil
	}))
	for _, req := range []*http.Request{
		httptest.NewRequest("GET", "/containers/order-manager-api/logs", strings.NewReader("body")),
		httptest.NewRequest("GET", "/containers/order-manager-api/logs", nil),
	} {
		if req.ContentLength == 0 {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
		}
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("got %d, want 403", rec.Code)
		}
	}
}

func TestInspectionReturnsOnlyAllowedFields(t *testing.T) {
	for _, status := range []int{200, 404} {
		handler := dockerLogsHandler(roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: status, Header: http.Header{"X-Private": {"fixture-secret"}}, Request: r,
				Body: io.NopCloser(strings.NewReader(`{"State":{"Running":true,"FinishedAt":"2026-01-01T00:00:00Z","Error":"private"},"Config":{"Tty":false,"Env":["DB_PASSWORD=fixture-secret"]},"Mounts":["private"]}`)),
			}, nil
		}))
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, httptest.NewRequest("GET", "/containers/order-manager-db/json", nil))
		want := ""
		if status == 200 {
			want = `{"State":{"Running":true,"FinishedAt":"2026-01-01T00:00:00Z"},"Config":{"Tty":false}}`
		}
		if rec.Code != status || rec.Body.String() != want || rec.Header().Get("X-Private") != "" {
			t.Fatal("inspection response did not match the allowlist")
		}
	}
}
