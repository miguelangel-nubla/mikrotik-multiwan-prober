package main

import (
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"sync"
	"time"
)

func ipHandler(w http.ResponseWriter, r *http.Request) {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	// We use Fprintf to write the host string to the response body efficiently.
	// For plaintext response, we also set the Content-Type header.
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprint(w, host)
}

func startServer(addr string, port int, wg *sync.WaitGroup) {
	defer wg.Done()

	mux := http.NewServeMux()
	mux.HandleFunc("/", ipHandler)

	server := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", addr, port),
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	fmt.Printf("Starting server on %s:%d...\n", addr, port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		fmt.Fprintf(os.Stderr, "Error on port %d: %v\n", port, err)
	}
}

func main() {
	var (
		listenAddr string
		startPort  int
		endPort    int
	)

	flag.StringVar(&listenAddr, "addr", "", "Address to listen on")
	flag.IntVar(&startPort, "start-port", 2000, "Starting port range")
	flag.IntVar(&endPort, "end-port", 2010, "Ending port range")
	flag.Parse()

	if startPort > endPort {
		fmt.Fprintf(os.Stderr, "Error: start-port (%d) cannot be greater than end-port (%d)\n", startPort, endPort)
		os.Exit(1)
	}

	var wg sync.WaitGroup
	for port := startPort; port <= endPort; port++ {
		wg.Add(1)
		go startServer(listenAddr, port, &wg)
	}

	wg.Wait()
}
