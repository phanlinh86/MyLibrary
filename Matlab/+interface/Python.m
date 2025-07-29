% import java.io.*;
% import java.net.*;
% These import statements are commented out because MATLAB's
% Java integration typically handles them automatically,
% but they are good for clarity.

classdef Python < handle
    %BASE A MATLAB class to communicate with a Python socket server.
    %   This class provides methods to connect to a Python server,
    %   send commands, and receive responses.

    properties (Access=public)
        sock = nan;         % Java Socket object for communication
        in = nan;           % Java BufferedReader for input stream
        out = nan;          % Java PrintWriter for output stream

        % Host and port for the Python server
        host = '127.0.0.1'; % Default host name
        port = 12346;       % Default port number

        % Path to Python library. The MATLAB server is under
        % libpath\interface\matlab.py
        libpath = [];

        % Expected hello message from the Python server.
        % This must exactly match what the Python server sends (after stripping newline).
        helloMsg = 'Hello from Python server!';
        DEBUG = 1;
    end

    methods (Access=public)
        % Constructor
        function obj = Python(varargin)
            % BASE Constructor
            %   obj = Python() creates an object with default host and port.
            %   obj = Python(host) sets a custom host.
            %   obj = Python(host, port) sets custom host and port.
            if nargin >= 1
                obj.host = varargin{1};
            end
            if nargin >= 2
                obj.port = varargin{2};
            end
            if nargin >= 3
                obj.libpath = varargin{3};
            end
        end

        % Start the Python server (assumes 'python_server.py' is in the same directory)
        function serve(self, runInBackGround)
            % SERVE Starts the Python server process.
            %   This function attempts to execute 'python python_server.py'
            %   It uses 'start' on Windows to run it in a new console window.
            if nargin == 1
                runInBackGround = 0; % Default to foreground if not specified
            end

            try
                % Determine the full path to the Python server script
                % Assumes the Python script is named 'python_server.py'
                % and is in the same directory as this MATLAB class file.
                if isempty(self.libpath)
                    mainPath = strsplit(mfilename('fullpath'), filesep);
                    mainPath = strjoin(mainPath(1:end-3), filesep);
                    self.libpath = [mainPath '\Python'];                    
                end
                scriptPath = [self.libpath '\interface\matlab.py'];

                % Construct the command to start the Python server.
                % 'start' is a Windows command to run a program in a new window.
                % For Linux/macOS, you might use '&' or a dedicated terminal command.
                if ispc % Windows
                    if runInBackGround
                        command = sprintf('start "Python Server" /b python "%s"', scriptPath);
                    else
                        command = sprintf('start python "%s"', scriptPath);
                    end
                else % Unix-like (Linux/macOS) - might need adjustment for specific setups
                    command = sprintf('python "%s" &', scriptPath); % '&' runs in background
                end

                fprintf('Attempting to start Python server with command:\n%s\n', command);
                [status, cmdout] = system(command);

                if status ~= 0
                    error('MATLAB:PythonServerStartFailed', ...
                          'Failed to start Python server (status %d): %s\n', status, cmdout);
                else
                    disp('Python server initiated. Check its console for output.');
                end
            catch ME
                error('MATLAB:PythonServerServeError', 'Error starting Python server: %s', ME.message);
            end
        end

        % Connect to the Python server
        function connect(self, host, port)
            % CONNECT Establishes a socket connection to the Python server.
            %   connect(self) uses the object's default host and port.
            %   connect(self, host, port) specifies host and port for connection.
            if nargin >= 2
                self.host = host;
            end
            if nargin >= 3
                self.port = port;
            end

            fprintf('Attempting to connect to %s:%d...\n', self.host, self.port);
            try
                % Create a new socket connection
                self.sock = java.net.Socket(self.host, self.port);
                % Get input and output streams
                self.in = java.io.BufferedReader(java.io.InputStreamReader(self.sock.getInputStream));
                self.out = java.io.PrintWriter(self.sock.getOutputStream, true); % 'true' for autoFlush

                % Read the initial hello message from the Python server
                receivedHello = self.read(); % read() method handles char conversion and newline stripping
                fprintf('Received from server: "%s"\n', receivedHello);

                % Check if the received message matches the expected hello message
                if strcmp(receivedHello, self.helloMsg)
                    fprintf("Connected to %s port %d successfully !!!\n", self.host, self.port);
                else
                    error("Connection failed: Unexpected hello message '%s'. Expected '%s'.", ...
                          receivedHello, self.helloMsg);
                end
            catch ME
                % Catch and rethrow any connection errors
                error('MATLAB:PythonSocketConnectionError', 'Connection Error: %s', ME.message);
            end
        end

        % Send a string to the Python server
        function flush(self)
            % FLUSHINPUTBUFFER Reads and discards all available lines in the input buffer.
            while self.in.ready()
                self.in.readLine();
            end
        end

        function write(self, str)
            % WRITE Sends a string message to the connected Python server.
            %   write(self, str) sends 'str' followed by a newline.
            if isempty(self.sock) || ~self.sock.isConnected()
                error('MATLAB:PythonSocketNotConnected', 'Cannot write: Not connected to the Python server.');
            end
            self.flush(); % Clear any leftover responses
            self.out.println(str); % println adds a newline, which the Python server expects
            if self.DEBUG
                fprintf('Sent: "%s"\n', str); % For debugging
            end
        end

        % Read a response string from the Python server
        function response = read(self, timeout)
            % READ Reads a line of text from the Python server with optional timeout.
            %   response = read(self, timeout) returns the received string or empty if timed out.
            if isempty(self.sock) || ~self.sock.isConnected()
                error('MATLAB:PythonSocketNotConnected', 'Cannot read: Not connected to the Python server.');
            end
            if nargin < 2
                timeout = 10; % default timeout in seconds
            end
            tStart = tic;
            while true
                if self.in.ready()
                    response = char(self.in.readLine());
                    return;
                end
                if toc(tStart) > timeout
                    % warning('Python server read timed out.');
                    response = '';
                    return;
                end
                pause(0.001); % avoid busy-waiting
            end
        end

        % Disconnect from the Python server (client-side only)
        function disconnect(self)
            % DISCONNECT Closes the socket connection to the Python server.
            if ~isempty(self.sock) && self.sock.isConnected()
                self.sock.close();
                fprintf('Connection to Python server closed.\n');
            else
                fprintf('No active connection to close.\n');
            end
            self.sock = nan;
            self.in = nan;
            self.out = nan;
        end

        % Close the Python server and disconnect
        function close(self)
            % CLOSE Sends a shutdown command to the Python server and disconnects.
            if isempty(self.sock) || ~self.sock.isConnected()
                fprintf('No active connection to close server.\n');
                return;
            end
            try
                self.write('/close'); % Assumes 'close' is the shutdown command for the server
                response = self.read(5);
                fprintf('Server response to close: "%s"\n', response);
            catch ME
                error('MATLAB:PythonSocketCloseError', 'Close Error: %s', ME.message);
                % warning('Error sending close command: %s', ME.message);
            end
            self.disconnect();
        end


        % --- Command Sending Methods ---

        function result = eval(self, evalStr)
            % EVAL Sends an '/eval' command to the Python server.
            %   result = eval(self, evalStr) evaluates 'evalStr' on the server
            %   and returns the parsed result.
            self.write(sprintf('/eval %s', evalStr));
            while true
                line = self.read();
                if startsWith(line, '[PYTHON_PRINT]')
                    % Print everything after the marker
                    disp(strrep(line, '[PYTHON_PRINT]', ''));
                elseif startsWith(line, 'Result: ')
                    response = line(length('Result: ') + 1:end);
                    break;
                elseif startsWith(line, 'Eval error:')
                    warning(line);
                    break;
                else
                    % Collect or print any other lines if needed
                    disp(line);
                end
            end
            if exist('response', 'var')
                result = self.parsePythonResultString(response);
            end
        end

        function response = exec(self, execStr)
            % EXEC Sends an '/exec' command to the Python server.
            %   response = exec(self, execStr) executes 'execStr' on the server
            %   and returns the server's confirmation message.
            self.write(sprintf('/exec %s', execStr));
            response = self.read(); % Python server now sends a confirmation
        end

        function result = get(self, varName)
            % GET Retrieves a variable from the Python server.
            %   result = get(self, varName) automatically detects struct/dict via JSON.
            % If not JSON, fall back to regular get
            self.write(sprintf('/get %s', varName));
            response = self.read();
            try
                result = jsondecode(response);
            catch
                result = self.parsePythonResultString(response);
            end
        end

        function response = set(self, varName, varValue, varargin)
            % SET Sends a '/set' command to the Python server.
            %   response = set(self, varName, varValue) sets a variable 'varName'
            %   to 'varValue' on the server. 'varValue' will be stringified.
            %   Supports numeric arrays (1D/2D) and scalars.
            %   Optional: set(self, varName, varValue, 'numpy', true) to send as numpy array.

            sendAsNumpy = false;
            if nargin > 3 && strcmp(varargin{1}, 'numpy') && varargin{2} == true
                sendAsNumpy = true;
            end

            formattedValue = '';
            if ischar(varValue) || isstring(varValue)
                % Enclose string values in single quotes for Python's eval
                % Handle existing single quotes within the string by escaping them
                formattedValue = sprintf('''%s''', strrep(varValue, '''', ''''''));
            elseif isnumeric(varValue) && (ismatrix(varValue) || isscalar(varValue))
                if isscalar(varValue)
                    formattedValue = num2str(varValue);
                else % Handle 1D and 2D arrays
                    [rows, cols] = size(varValue);
                    if rows == 1 || cols == 1 % 1D array (vector)
                        % Convert to Python list format [val1, val2, ...]
                        formattedValue = '[';
                        for i = 1:numel(varValue)
                            formattedValue = [formattedValue, num2str(varValue(i))]; %#ok<AGROW>
                            if i < numel(varValue)
                                formattedValue = [formattedValue, ', ']; %#ok<AGROW>
                            end
                        end
                        formattedValue = [formattedValue, ']'];
                    else % 2D array (matrix)
                        % Convert to Python list of lists format [[row1_vals], [row2_vals], ...]
                        formattedValue = '[';
                        for i = 1:rows
                            formattedValue = [formattedValue, '[']; %#ok<AGROW>
                            for j = 1:cols
                                formattedValue = [formattedValue, num2str(varValue(i, j))]; %#ok<AGROW>
                                if j < cols
                                    formattedValue = [formattedValue, ', ']; %#ok<AGROW>
                                end
                            end
                            formattedValue = [formattedValue, ']']; %#ok<AGROW>
                            if i < rows
                                formattedValue = [formattedValue, ', ']; %#ok<AGROW>
                            end
                        end
                        formattedValue = [formattedValue, ']'];
                    end
                    if sendAsNumpy
                        formattedValue = ['np.array(', formattedValue, ')'];
                    end
                end
            elseif islogical(varValue)
                formattedValue = lower(string(varValue)); % 'true' or 'false'
            else
                warning('MATLAB:PythonSocketSetUnsupportedType', ...
                        'Unsupported variable type for /set command. Converting to string directly, might not be Python-compatible: %s', class(varValue));
                formattedValue = mat2str(varValue); % Fallback
            end

            command = sprintf('/set %s=%s', varName, formattedValue);
            self.write(command);
            response = self.read(); % Read the server's confirmation
        end

        function response = set_struct(self, varName, structObj)
            % SET_STRUCT Sends a MATLAB struct as JSON to the Python server.
            %   response = set_struct(self, varName, structObj) sets a variable on the server.
            jsonStr = jsonencode(structObj);
            % Escape any problematic characters for Python eval
            % Use /set_json <varName> <jsonStr>
            self.write(sprintf('/set_json %s %s', varName, jsonStr));
            response = self.read();
        end

        function structObj = get_struct(self, varName)
            % GET_STRUCT Gets a struct variable from the Python server (expects JSON).
            self.write(sprintf('/get_json %s', varName));
            jsonStr = self.read();
            structObj = jsondecode(jsonStr);
        end
    end

    methods (Access=private)
        function parsedValue = parsePythonResultString(self, pythonString)
            % parsePythonResultString Parses a string received from Python into a MATLAB data type.
            %   Handles numbers, strings, and Python list/NumPy array string representations.

            pythonString = strtrim(pythonString); % Remove leading/trailing whitespace

            % Try to parse as a number
            [num, status] = str2num(pythonString); %#ok<ST2NM>
            if status && ~isempty(pythonString) && (isnumeric(num) || islogical(num))
                parsedValue = num; % It's a simple number or boolean
                return;
            end

            % Check for Python string literal format (e.g., 'hello', "world")
            if (startsWith(pythonString, '''') && endsWith(pythonString, '''')) || ...
               (startsWith(pythonString, '"') && endsWith(pythonString, '"'))
                % Remove quotes and unescape internal quotes if necessary (simple unescape for now)
                parsedValue = strrep(pythonString(2:end-1), '''''', '''');
                return;
            end

            % Check for Python list or NumPy array string representation
            % e.g., "[1, 2, 3]", "[[1, 2], [3, 4]]", "array([1, 2])"
            if (startsWith(pythonString, '[') && endsWith(pythonString, ']')) || ...
               (startsWith(pythonString, 'array([') && endsWith(pythonString, '])'))

                % Remove prefixes and suffixes to get raw content
                if startsWith(pythonString, 'array(')
                    content = pythonString(length('array(')+1 : end-1); % Remove 'array(' and ')'
                else
                    content = pythonString;
                end
                
                % Remove outer brackets for primary parsing
                if startsWith(content, '[') && endsWith(content, ']')
                    content = content(2:end-1);
                end

                % Split by top-level commas to distinguish rows/elements
                % This is a simplified split; robust parsing might need more advanced logic
                % (e.g., handling commas within sub-lists).
                elements_str = regexp(content, '\[.*?\]|[^,]+', 'match'); % Matches [] blocks or non-comma text

                num_elements = length(elements_str);
                if num_elements == 0
                    parsedValue = []; % Empty list/array
                    return;
                end

                % Determine if it's a 1D or 2D structure
                is2D = false;
                if num_elements > 0 && startsWith(strtrim(elements_str{1}), '[')
                    is2D = true;
                end

                if is2D
                    % It's a list of lists (2D array)
                    num_rows = num_elements;
                    parsed_rows = cell(1, num_rows);
                    for i = 1:num_rows
                        row_str = strtrim(elements_str{i});
                        % Remove outer brackets for the row and split by comma
                        row_content = row_str(2:end-1); % Remove [ ]
                        row_elements = strsplit(row_content, ',');
                        
                        current_row_vals = [];
                        for j = 1:length(row_elements)
                            val_str = strtrim(row_elements{j});
                            [val, status_val] = str2num(val_str); %#ok<ST2NM>
                            if status_val && ~isempty(val_str)
                                current_row_vals = [current_row_vals, val]; %#ok<AGROW>
                            else
                                warning('MATLAB:PythonSocketParseError', 'Could not parse element "%s" in row.', val_str);
                                current_row_vals = [current_row_vals, NaN]; %#ok<AGROW>
                            end
                        end
                        parsed_rows{i} = current_row_vals;
                    end
                    
                    % Concatenate rows to form a 2D matrix
                    if ~isempty(parsed_rows)
                        % Find max columns to pad if rows have different lengths
                        max_cols = 0;
                        for i = 1:num_rows
                            max_cols = max(max_cols, length(parsed_rows{i}));
                        end
                        
                        % Create an empty matrix and fill it
                        parsedValue = NaN(num_rows, max_cols);
                        for i = 1:num_rows
                            parsedValue(i, 1:length(parsed_rows{i})) = parsed_rows{i};
                        end
                    else
                        parsedValue = [];
                    end

                else
                    % It's a 1D array (simple list of numbers)
                    parsed_vals = [];
                    for i = 1:num_elements
                        val_str = strtrim(elements_str{i});
                        [val, status_val] = str2num(val_str); %#ok<ST2NM>
                        if status_val && ~isempty(val_str)
                            parsed_vals = [parsed_vals, val]; %#ok<AGROW>
                        else
                            warning('MATLAB:PythonSocketParseError', 'Could not parse element "%s".', val_str);
                            parsed_vals = [parsed_vals, NaN]; %#ok<AGROW>
                        end
                    end
                    parsedValue = parsed_vals;
                end
                return;
            end

            % If nothing else matches, return as a plain string
            parsedValue = pythonString;
        end
    end
end
