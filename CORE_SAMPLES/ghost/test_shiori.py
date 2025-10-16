#!/usr/bin/env python3
import sys
import time

def main():
    while True:
        try:
            request = ""
            while True:
                line = sys.stdin.readline()
                if not line:
                    break
                request += line
                if line.strip() == "":
                    break
            
            if not request:
                break
            
            lines = request.strip().split('\n')
            event_id = ""
            
            for line in lines:
                if line.startswith("ID: "):
                    event_id = line[4:]
                    break
            
            response = ""
            if event_id == "OnBoot":
                response = "\\h\\s[0]こんにちは！MacUkagakaです。\\e"
            elif event_id == "OnMouseClick":
                response = "\\h\\s[1]クリックありがとう！\\e"
            elif event_id == "OnSecondChange":
                response = "\\h\\s[0]元気にしています。\\e"
            elif event_id == "OnClose":
                response = "\\h\\s[0]さようなら！\\e"
            
            shiori_response = f"SHIORI/3.0 200 OK\r\n"
            shiori_response += f"Content-Type: text/plain\r\n"
            shiori_response += f"Value: {response}\r\n"
            shiori_response += f"\r\n"
            
            sys.stdout.write(shiori_response)
            sys.stdout.flush()
            
        except Exception as e:
            break

if __name__ == "__main__":
    main()