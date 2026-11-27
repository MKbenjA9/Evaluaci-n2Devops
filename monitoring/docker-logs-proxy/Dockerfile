FROM golang:1.26.10-alpine3.24 AS builder
WORKDIR /src
COPY main.go main_test.go ./
RUN CGO_ENABLED=0 go test -v main.go main_test.go
RUN CGO_ENABLED=0 go build -o /docker-logs-proxy main.go

FROM scratch
COPY --from=builder /docker-logs-proxy /docker-logs-proxy
USER 65534:65534
ENTRYPOINT ["/docker-logs-proxy"]
