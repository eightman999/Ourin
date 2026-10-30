// Ourin's macOS SHIOLINK entry for the unchanged upstream Gohst callbacks.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	shiori "github.com/Narazaka/shiorigo"
	"github.com/kurousada/gohst/internal/requesthandlers"
)

type host struct{ loaded bool }

func (h *host) load(directory string) error {
	if h.loaded {
		return errors.New("duplicate load")
	}
	if !filepath.IsAbs(directory) {
		return errors.New("load path must be absolute")
	}
	directory = filepath.Clean(directory)
	info, err := os.Stat(directory)
	if err != nil || !info.IsDir() {
		return errors.New("load directory does not exist")
	}
	if err := requesthandlers.OnLoad(directory); err != nil {
		return err
	}
	h.loaded = true
	return nil
}

func (h *host) unload() error {
	if !h.loaded {
		return nil
	}
	if err := requesthandlers.OnUnload(); err != nil {
		return err
	}
	h.loaded = false
	return nil
}

func (h *host) request(wire string) string {
	response := requesthandlers.ResponseInternalServerError()
	if h.loaded {
		request, err := shiori.ParseRequest(wire)
		if err != nil {
			response = requesthandlers.ResponseBadRequest()
		} else {
			response, err = requesthandlers.OnRequest(request)
			if err != nil {
				response = requesthandlers.ResponseInternalServerError()
			}
		}
	}
	response.Headers["Charset"] = "UTF-8"
	response.Headers["Sender"] = "gohst"
	return response.String()
}

func run(input io.Reader, output io.Writer) error {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), 1048576)
	writer := bufio.NewWriter(output)
	h := host{}
	for scanner.Scan() {
		line := strings.TrimSuffix(scanner.Text(), "\r")
		switch {
		case strings.HasPrefix(line, "*L:"):
			if err := h.load(line[3:]); err != nil {
				return err
			}
		case line == "*U:":
			return h.unload()
		case strings.HasPrefix(line, "*S:"):
			if _, err := fmt.Fprintf(writer, "%s\r\n", line); err != nil {
				return err
			}
			if err := writer.Flush(); err != nil {
				return err
			}
			var lines []string
			size := 0
			complete := false
			for scanner.Scan() {
				requestLine := strings.TrimSuffix(scanner.Text(), "\r")
				size += len(requestLine) + 2
				if size > 1048576 {
					return errors.New("request too large")
				}
				lines = append(lines, requestLine)
				if requestLine == "" {
					complete = true
					break
				}
			}
			if !complete {
				return errors.New("incomplete request")
			}
			if _, err := writer.WriteString(h.request(strings.Join(lines, "\r\n") + "\r\n")); err != nil {
				return err
			}
			if err := writer.Flush(); err != nil {
				return err
			}
		default:
			return errors.New("invalid SHIOLINK command")
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return nil
}

func main() {
	log.SetOutput(os.Stderr)
	if err := run(os.Stdin, os.Stdout); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
