# server.py
import argparse
import socketserver
import sys
import io
import numpy as np
import logging
import json
import os

# Default
DEFAULT_HOST, DEFAULT_PORT = "127.0.0.1", 12346

# Global dictionary to store variables
global_vars = {}

# --- Main Request Handler ---
class MatlabTcpHandler(socketserver.BaseRequestHandler):
    """
    The request handler class for our server.

    It is instantiated once per connection to the client, and handles
    all communication at that point.
    """

    def handle(self):
        # Send initial "Hello" message
        self.request.sendall(b"Hello from Python server!\n")
        logging.info('Client connected and sent hello.', extra={'client': self.client_address})

        while True:
            try:
                # Read a line from the client (command)
                # Using a file-like object for convenience with readline()
                # A BufferedReader with timeout would be more robust for production
                client_file = self.request.makefile('r', encoding='utf-8')
                command_line = client_file.readline().strip()

                if not command_line:
                    # Client disconnected
                    logging.info('Client disconnected.', extra={'client': self.client_address})
                    break

                logging.info(f"Received command: '{command_line}'", extra={'client': self.client_address})

                parts = command_line.split(' ', 1)
                cmd = parts[0]
                arg = parts[1] if len(parts) > 1 else ''
                try:
                    if cmd == '/eval':
                        # Redirect stdout to capture print statements from eval
                        old_stdout = sys.stdout
                        redirected_output = io.StringIO()
                        sys.stdout = redirected_output
                        try:
                            result = eval(arg, globals(), global_vars)
                        except Exception as e:
                            sys.stdout = old_stdout
                            logging.error(f"Eval error: {e}", extra={'client': self.client_address})
                            self.request.sendall(str.encode(f"Eval error: {e}\n"))
                            continue  # Skip to the next command

                        sys.stdout = old_stdout  # Restore stdout

                        captured_output = redirected_output.getvalue()
                        if captured_output:
                            self.request.sendall(f"[PYTHON_PRINT]{captured_output}".encode('utf-8'))
                        if not isinstance(result, str):
                            self.request.sendall(f"Result: "
                                                    f"{f"{result}".replace(']\n', '];').replace('\n', ',')}"
                                                    f"\n".encode('utf-8'))
                        else:
                            self.request.sendall(f"Result: {result}\n".encode('utf-8'))

                    elif cmd == '/exec':
                        exec(arg, globals(), global_vars)
                        self.request.sendall(b"Exec success\n")

                    elif cmd == '/get':
                        if arg in global_vars:
                            result = global_vars[arg]
                            if not isinstance(result, str):
                                self.request.sendall(str.encode(f""
                                                        f"{f"{result}".replace(']\n', '];').replace('\n', ',')}"
                                                        f"\n"))
                            else:
                                self.request.sendall(str.encode(f'"{result}"\n'))
                        else:
                            self.request.sendall(f"Error: Variable '{arg}' not found\n".encode('utf-8'))

                    elif cmd == '/set':
                        var_name, var_expr = arg.split('=', 1)
                        var_name = var_name.strip()
                        var_value = eval(var_expr, globals(), global_vars)
                        global_vars[var_name] = var_value
                        self.request.sendall(f"Set '{var_name}' to {repr(var_value)} success\n".encode('utf-8'))

                    elif cmd == '/set_json':
                        # /set_json <varName> <jsonStr>
                        var_name, json_str = arg.split(' ', 1)
                        var_name = var_name.strip()
                        try:
                            var_value = json.loads(json_str)
                        except Exception as e:
                            self.request.sendall(f"Set JSON error: {e}\n".encode('utf-8'))
                            continue
                        global_vars[var_name] = var_value
                        self.request.sendall(f"Set JSON '{var_name}' success\n".encode('utf-8'))

                    elif cmd == '/get_json':
                        var_name = arg.strip()
                        if var_name in global_vars:
                            try:
                                json_str = json.dumps(global_vars[var_name])
                                self.request.sendall((json_str + '\n').encode('utf-8'))
                            except Exception as e:
                                self.request.sendall(f"Get JSON error: {e}\n".encode('utf-8'))
                        else:
                            self.request.sendall(f"Error: Variable '{var_name}' not found\n".encode('utf-8'))

                    elif cmd == '/exit':
                        print(f"Client {self.client_address} requested exit.")
                        break  # Break out of the loop to close connection

                    elif cmd == '/close':
                        print(f"Client {self.client_address} requested server shutdown.")
                        self.request.sendall(b"Server shutting down.\n")
                        # Shutdown the server in a new thread to avoid blocking
                        import threading
                        threading.Thread(target=self.server.shutdown, daemon=True).start()
                        break

                    else:
                        print(f"Unrecognized command: '{command_line}'")
                        self.request.sendall(str.encode(f"Unrecognized command: '{command_line}'\n"))

                except Exception as e:
                    logging.error(f"Exception while handling command '{command_line}': {e}", extra={'client': self.client_address})
                    self.request.sendall(str.encode(f"Server error: {e}\n"))

            except ConnectionResetError:
                logging.warning('Client forcibly closed the connection.', extra={'client': self.client_address})
                break
            except BrokenPipeError:
                logging.warning('Broken pipe to client. Connection lost.', extra={'client': self.client_address})
                break
            except Exception as e:
                logging.error(f"An error occurred: {e}", extra={'client': self.client_address})
                break


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    pass


def start_server(host, port):
    server = ThreadedTCPServer((host, port), MatlabTcpHandler)
    server.daemon_threads = True  # Allow server to exit when main thread exits
    # Setup path to main project directory
    main_path = '\\'.join(os.path.realpath(__file__).split('\\')[:-2])  # Main path of the whole project
    print(f"Setup path for Python Server: {main_path}")
    if main_path not in sys.path:
        sys.path.append(main_path)
    # Start the server
    print(f"Python server listening on {host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nPython server shutting down.")
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    # Get host and port from command line arguments if provided
    parser = argparse.ArgumentParser(prog="Matlab-Python TCP Server",
                                         description="A TCP server to execute Python commands from MATLAB.")
    parser.add_argument('--host', type=str, default=DEFAULT_HOST)
    parser.add_argument('--port', type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)s %(client)s %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    start_server(args.host, args.port)