package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var containerPath = regexp.MustCompile(`\A(?:/v1\.[0-9]{1,3})?/containers/(order-manager-api|order-manager-db)/(json|logs)\z`)
var apiMetadata = regexp.MustCompile(`\A(?:/v1\.[0-9]{1,3})?/(?:_ping|version)\z`)
var pingPath = regexp.MustCompile(`\A(?:/v1\.[0-9]{1,3})?/_ping\z`)

type inspection struct {
	State struct {
		Running    bool
		FinishedAt string
	}
	Config struct {
		Tty bool
	}
}

func dockerLogsHandler(transport http.RoundTripper) http.Handler {
	upstream := &url.URL{Scheme: "http", Host: "docker"}
	proxy := &httputil.ReverseProxy{
		Transport: transport,
		Rewrite: func(request *httputil.ProxyRequest) {
			request.SetURL(upstream)
			request.Out.Header = make(http.Header)
		},
		FlushInterval: -1,
		ModifyResponse: func(response *http.Response) error {
			if !strings.HasSuffix(response.Request.URL.Path, "/json") {
				return nil
			}
			defer response.Body.Close()
			if response.StatusCode != http.StatusOK {
				response.Header = make(http.Header)
				response.Body = http.NoBody
				response.ContentLength = 0
				return nil
			}
			var allowed inspection
			if err := json.NewDecoder(io.LimitReader(response.Body, 4<<20)).Decode(&allowed); err != nil {
				return err
			}
			body, err := json.Marshal(allowed)
			if err != nil {
				return err
			}
			response.Header = http.Header{"Content-Type": {"application/json"}}
			response.Body = io.NopCloser(strings.NewReader(string(body)))
			response.ContentLength = int64(len(body))
			return nil
		},
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		metadata := apiMetadata.MatchString(path)
		target := containerPath.FindStringSubmatch(path)
		if r.RequestURI != r.URL.RequestURI() || r.URL.RawPath != "" || r.URL.ForceQuery ||
			r.ContentLength != 0 || len(r.TransferEncoding) != 0 || r.Header.Get("Upgrade") != "" ||
			(r.Method != http.MethodGet && !(r.Method == http.MethodHead && pingPath.MatchString(path))) ||
			(!metadata && target == nil) {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		if target != nil && target[2] == "logs" {
			query, err := url.ParseQuery(r.URL.RawQuery)
			if err != nil || !validLogQuery(query) {
				w.WriteHeader(http.StatusForbidden)
				return
			}
			r.URL.RawQuery = query.Encode()
		} else if r.URL.RawQuery != "" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		proxy.ServeHTTP(w, r)
	})
}

func validLogQuery(query url.Values) bool {
	for key, values := range query {
		if len(values) != 1 {
			return false
		}
		value := values[0]
		switch key {
		case "stdout", "stderr", "follow", "timestamps":
			if value != "1" && value != "0" && value != "true" && value != "false" {
				return false
			}
		case "since":
			if _, err := strconv.ParseUint(value, 10, 63); err != nil {
				return false
			}
		default:
			return false
		}
	}
	return true
}

func main() {
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, "unix", "/var/run/docker.sock")
		},
		ResponseHeaderTimeout: 15 * time.Second,
	}
	server := &http.Server{
		Addr:              ":2375",
		Handler:           dockerLogsHandler(transport),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}
