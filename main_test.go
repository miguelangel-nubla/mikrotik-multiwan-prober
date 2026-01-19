package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIpHandler(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	// Set a remote address to test
	req.RemoteAddr = "1.2.3.4:1234"

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(ipHandler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	expected := "1.2.3.4"
	if rr.Body.String() != expected {
		t.Errorf("handler returned unexpected body: got %v want %v",
			rr.Body.String(), expected)
	}
}

func TestIpHandlerIPv6(t *testing.T) {
	req, err := http.NewRequest("GET", "/", nil)
	if err != nil {
		t.Fatal(err)
	}

	// Set an IPv6 remote address to test
	req.RemoteAddr = "[2001:db8::1]:1234"

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(ipHandler)

	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v",
			status, http.StatusOK)
	}

	expected := "2001:db8::1"
	if rr.Body.String() != expected {
		t.Errorf("handler returned unexpected body: got %v want %v",
			rr.Body.String(), expected)
	}
}
