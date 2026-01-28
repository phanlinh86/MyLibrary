% import java.io.*;
% import java.net.*;
% These import statements are commented out because MATLAB's
% Java integration typically handles them automatically,
% but they are good for clarity.

classdef Python < dynamicprops
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
        DEBUG = 0;
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

        % Add path for Python server
        function addpath(self, path)
            self.exec(['sys.path.append("' strrep(path, '\', '/') '")']);
        end
        
        % Import everything in a module or a class from a module
        function import(self, module, varargin)
            class = [];
            if nargin >= 3
                class = varargin{1};
            end
            if ~isempty(class)
                self.exec(sprintf('from %s import %s', module, class));
            else
                self.exec(sprintf('from %s import %', module));
            end
        end
        % Create a new object from a class
        function newObj = new(self, class)
            % NEW Creates a new instance of a Python class.
            %   obj = new(self, class) creates a new instance of the specified class.
            objName = sprintf('obj_%s_%d', class, randi(1e9)); % Unique object name
            self.exec(sprintf('%s = %s()', objName, class));
            newObj = self.getObject(objName);
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

                % Add host and port as arguments to the script
                scriptCmd = sprintf('"%s" --host=%s --port=%d', scriptPath, self.host, self.port);

                % Construct the command to start the Python server.
                % 'start' is a Windows command to run a program in a new window.
                % For Linux/macOS, you might use '&' or a dedicated terminal command.
                if ispc % Windows
                    if runInBackGround
                        command = sprintf('start "Python Server" /b python %s', scriptCmd);
                    else
                        command = sprintf('start python %s', scriptCmd);
                    end
                else % Unix-like (Linux/macOS) - might need adjustment for specific setups
                    command = sprintf('python %s &', scriptCmd); % '&' runs in background
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
                if contains(response, 'object at ')
                    result = self.getObject(evalStr);
                else
                    result = self.parsePythonResultString(response);
                end
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
            result = self.eval(varName);
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

            command = sprintf('/exec %s=%s', varName, formattedValue);
            self.write(command);
            response = self.read(); % Read the server's confirmation
        end

        function obj = getObject(self, varName)
            % MIRROR Create a MATLAB object for a Python object without external helpers.
            %   obj = mirror(self, varName) queries the Python server for
            %   callable attributes of the Python variable named `varName` and
            %   returns a lightweight MATLAB object. The object is an
            %   instance of `dynamicprops` whose properties are function
            %   handles that forward calls to the remote Python object using
            %   the existing `eval`/`set`/`get` methods on this Python client.
            %
            %   Limitations: only positional arguments are supported for method
            %   calls; supported MATLAB argument types: char/string, numeric
            %   scalars/vectors/matrices, and logicals.

            if nargin < 2 || isempty(varName)
                error('MATLAB:PythonMirrorObject:MissingVarName', 'A Python variable name must be provided.');
            end

            % Query Python for callable attribute names (exclude dunder names)
            try
                pyExpr = sprintf('[name for name in dir(%s) if callable(getattr(%s, name)) and not name.startswith("__")]', varName, varName);
                methodNames = self.eval(pyExpr);
            catch ME
                error('MATLAB:PythonMirrorObject:QueryFailed', 'Failed to query Python object ''%s'': %s', varName, ME.message);
            end

            % Normalize returned method names into a cell array of chars
            if ischar(methodNames)
                methodNames = {methodNames};
            elseif isstring(methodNames)
                methodNames = cellstr(methodNames);
            elseif isnumeric(methodNames) || islogical(methodNames)
                methodNames = arrayfun(@num2str, methodNames, 'UniformOutput', false);
            elseif iscell(methodNames)
                methodNames = cellfun(@(x) char(x), methodNames, 'UniformOutput', false);
            else
                methodNames = {};
            end
            methodNames = methodNames(~cellfun(@(x) isempty(x) || ~ischar(x), methodNames));

            % Create a dynamic python object (pythonobject is a concrete subclass of dynamicprops)
            obj = interface.pythonobject(self);
            % Attach metadata properties
            obj.name = varName;

            % Helper: convert MATLAB arg to a Python literal snippet
            function argPy = matlabArgToPython(arg)
                if ischar(arg) || isstring(arg)
                    s = char(arg);
                    s = strrep(s, '''', ''''''); % escape single quotes by doubling
                    argPy = ['''' s ''''];
                    return;
                end
                if isnumeric(arg)
                    if isscalar(arg)
                        argPy = num2str(arg);
                        return;
                    else
                        [r, c] = size(arg);
                        if r == 1 || c == 1
                            % 1D vector
                            parts = arrayfun(@(x) num2str(x), arg(:)', 'UniformOutput', false);
                            argPy = ['[' strjoin(parts, ', ') ']'];
                            return;
                        else
                            % 2D matrix -> list of lists
                            rows = cell(1, r);
                            for ii = 1:r
                                parts = arrayfun(@(x) num2str(x), arg(ii, :), 'UniformOutput', false);
                                rows{ii} = ['[' strjoin(parts, ', ') ']'];
                            end
                            argPy = ['[' strjoin(rows, ', ') ']'];
                            return;
                        end
                    end
                end
                if islogical(arg)
                    if isscalar(arg)
                        if arg
                            argPy = 'True';
                        else
                            argPy = 'False';
                        end
                        return;
                    else
                        % logical array -> Python list of True/False
                        vals = arrayfun(@(x) ternary(x, 'True', 'False'), arg(:), 'UniformOutput', false);
                        argPy = ['[' strjoin(vals, ', ') ']'];
                        return;
                    end
                end
                % Unsupported type
                error('MATLAB:PythonMirrorObject:UnsupportedArgType', 'Unsupported argument type: %s', class(arg));
            end

            % Small ternary helper (returns a or b depending on cond)
            function out = ternary(cond, a, b)
                if cond
                    out = a; else out = b; end
            end

            % Method-call wrapper used by all mirrored methods
            function out = callMethod(origName, varargin)
                % Convert args
                pyArgs = cell(1, numel(varargin));
                for kk = 1:numel(varargin)
                    pyArgs{kk} = matlabArgToPython(varargin{kk});
                end
                argsStr = strjoin(pyArgs, ', ');
                if isempty(argsStr)
                    expr = sprintf('%s.%s()', varName, origName);
                else
                    expr = sprintf('%s.%s(%s)', varName, origName, argsStr);
                end
                try
                    out = self.eval(expr);
                catch ME
                    error('MATLAB:PythonMirrorObject:MethodCallFailed', 'Failed calling %s.%s: %s', varName, origName, ME.message);
                end
            end

            % Add properties for each method: use a sanitized MATLAB name for property,
            % but keep the original Python name for invocation.
            for ii = 1:length(methodNames)
                orig = methodNames{ii};
                propName = matlab.lang.makeValidName(orig);
                % Avoid name collision with existing obj fields
                if isprop(obj, propName) || isfield(obj, propName)
                    propName = sprintf('%s_%d', propName, ii);
                end
                addprop(obj, propName);
                % Assign a function handle that calls the remote Python method
                obj.(propName) = @(varargin) callMethod(orig, varargin{:});
            end

            % Add simple getattr and setattr helpers
            addprop(obj, 'getattr');
            obj.getattr = @(attrName) self.eval(sprintf('%s.%s', varName, char(attrName)));

            addprop(obj, 'setattr');
            obj.setattr = @(attrName, val) self.set(sprintf('%s.%s', varName, char(attrName)), val);

            % Make obj read-only metadata helper
            addprop(obj, 'methods'); obj.methods = methodNames;

            % --- New: Mirror attributes from the Python object's __dict__ ---
            try
                % Request attribute names directly from __dict__ to avoid dunder and descriptors
                pyExprAttrs = sprintf('list(getattr(%s, "__dict__", {}).keys())', varName);
                attrNames = self.eval(pyExprAttrs);

                % Normalize returned attribute names into a cell array of chars
                if ischar(attrNames)
                    attrNames = {attrNames};
                elseif isstring(attrNames)
                    attrNames = cellstr(attrNames);
                elseif isnumeric(attrNames) || islogical(attrNames)
                    attrNames = arrayfun(@num2str, attrNames, 'UniformOutput', false);
                elseif iscell(attrNames)
                    attrNames = cellfun(@(x) char(x), attrNames, 'UniformOutput', false);
                else
                    attrNames = {};
                end
                attrNames = attrNames(~cellfun(@(x) isempty(x) || ~ischar(x), attrNames));

                % Add each attribute as a property on the MATLAB mirror object
                for ii = 1:length(attrNames)
                    orig = attrNames{ii};
                    propName = matlab.lang.makeValidName(orig);
                    % Avoid name collision with existing properties/methods
                    if isprop(obj, propName) || isfield(obj, propName)
                        propName = sprintf('%s_attr_%d', propName, ii);
                    end

                    % Try to fetch the attribute value. Use direct attribute access
                    % (e.g., objName.attr) so eval will mirror objects recursively if needed.
                    try
                        val = self.eval(sprintf('%s.%s', varName, orig));
                    catch
                        % Fallback: use getattr(...) with a quoted attribute name
                        try
                            val = self.eval(sprintf('getattr(%s, ''%s'')', varName, orig));
                        catch
                            val = [];
                        end
                    end

                    % Attach as a regular property (not a method)
                    addprop(obj, propName);
                    obj.(propName) = val;
                    attrNames{ii} = propName;
                end
                obj.attributes = attrNames;
            catch ME
                % Don't let attribute mirroring break object creation; warn instead
                warning('MATLAB:PythonMirrorObject:AttrQueryFailed', 'Failed to enumerate attributes for %s: %s', varName, ME.message);
            end
        end

    end

    methods (Access=private)
        function parsedValue = parsePythonResultString(self, pythonString)
            % parsePythonResultString Parses a string received from Python into a MATLAB data type.
            %   Handles numbers, strings, Python lists/arrays, and dictionaries (dict).
            %   Tries a quick JSON-normalization + jsondecode first, then falls back
            %   to a recursive parser for complex/malformed Python literal strings.

            pythonString = strtrim(pythonString); % Remove leading/trailing whitespace

            if isempty(pythonString)
                parsedValue = '';
                return;
            end

            % Quick numeric parse (preserve previous behavior)
            [num, status] = str2num(pythonString); %#ok<ST2NM>
            if status && ~isempty(pythonString) && (isnumeric(num) || islogical(num))
                parsedValue = num; % It's a simple number or boolean
                return;
            end

            % Quick string literal check (preserve previous behavior)
            if (startsWith(pythonString, '''') && endsWith(pythonString, '''')) || ...
               (startsWith(pythonString, '"') && endsWith(pythonString, '"'))
                % Remove surrounding quotes and unescape common escapes
                inner = pythonString(2:end-1);
                % Simple unescape for doubled single quotes
                inner = strrep(inner, '''''', '''');
                parsedValue = inner;
                return;
            end

            % NEW: If the server returned an unquoted string that contains whitespace
            % (for example: Result: abcdef as3tfff) and it doesn't contain any
            % structural characters like brackets, commas, or colons, treat the
            % entire line as a string instead of splitting on whitespace.
            if isempty(regexp(pythonString, '[,:\{\}\[\]\(\)]', 'once')) && ~isempty(regexp(pythonString, '\s', 'once'))
                parsedValue = pythonString;
                return;
            end

            % Attempt 1: Normalize common Python literal tokens to JSON and use jsondecode
            try
                s = pythonString;
                % Handle Python's array(...) wrapper e.g., array([1,2])
                if startsWith(s, 'array(')
                    % Extract the parentheses content if possible
                    % Find matching closing parenthesis - simple heuristic: remove leading 'array('
                    s = s(length('array(')+1 : end-1);
                end

                % Replace Python boolean/None literals with JSON equivalents
                s = regexprep(s, '\bTrue\b', 'true');
                s = regexprep(s, '\bFalse\b', 'false');
                s = regexprep(s, '\bNone\b', 'null');

                % Heuristic: convert single-quoted strings to double-quoted for json
                % This is a best-effort replacement and may fail on complex escaped inputs
                % Replace occurrences of '...' with "..." (non-greedy)
                s = regexprep(s, "(?<!\\)'([^']*)'", '"$1"');

                parsedValue = jsondecode(s);
                return;
            catch
                % If jsondecode fails, fall through to the recursive parser below
            end

            % Attempt 2: Recursive-descent parser for Python literals
            s = pythonString;
            % If it's wrapped by array(...) or dict(...), try to strip simple wrappers
            if startsWith(s, 'array(') && endsWith(s, ')')
                s = s(length('array(')+1:end-1);
            end

            idx = 1;
            n = length(s);

            % Helper: skip whitespace
            function skipws()
                while idx <= n && isspace(s(idx))
                    idx = idx + 1;
                end
            end

            % Helper: peek current char
            function c = peek()
                if idx <= n
                    c = s(idx);
                else
                    c = '';
                end
            end

            % Helper: consume and return next char
            function c = nextc()
                if idx <= n
                    c = s(idx);
                    idx = idx + 1;
                else
                    c = '';
                end
            end

            % Parse a value (object, array, string, number, boolean, None, bareword)
            function val = parseValue()
                skipws();
                ch = peek();
                if isempty(ch)
                    val = '';
                    return;
                end
                if ch == '{'
                    val = parseObject();
                    return;
                elseif ch == '['
                    val = parseArray();
                    return;
                elseif ch == '''' || ch == '"'
                    val = parseString();
                    return;
                else
                    % Could be True/False/None/number/bareword
                    token = parseToken();
                    if isempty(token)
                        val = '';
                        return;
                    end
                    if strcmp(token, 'True') || strcmpi(token, 'true')
                        val = true; return;
                    elseif strcmp(token, 'False') || strcmpi(token, 'false')
                        val = false; return;
                    elseif strcmp(token, 'None') || strcmpi(token, 'null')
                        val = [];
                        return;
                    end
                    % Try parse as number
                    num = str2double(token);
                    if ~isnan(num)
                        val = num; return;
                    end
                    % Fallback: return token as string
                    val = token;
                    return;
                end
            end

            % Parse an unquoted token until delimiter or whitespace
            function t = parseToken()
                skipws();
                start = idx;
                while idx <= n
                    ch = s(idx);
                    if any(ch == [',', ':', '}', ']', ' ' sprintf('\t') sprintf('\n') sprintf('\r') ])
                        break;
                    end
                    % also break on quotes
                    if ch == '''' || ch == '"'
                        break;
                    end
                    idx = idx + 1;
                end
                if idx > start
                    t = strtrim(s(start:idx-1));
                else
                    t = '';
                end
            end

            % Parse quoted string with escape handling
            function strv = parseString()
                quote = nextc(); % consume opening quote
                parts = '';
                while idx <= n
                    ch = nextc();
                    if isempty(ch)
                        break;
                    end
                    if ch == '\\'
                        % Escape sequence
                        if idx <= n
                            esc = nextc();
                            switch esc
                                case 'n'
                                    parts = [parts, char(10)];
                                case 't'
                                    parts = [parts, char(9)];
                                case 'r'
                                    parts = [parts, char(13)];
                                case ''''
                                    parts = [parts, ''''];
                                case '"'
                                    parts = [parts, '"'];
                                case '\\'
                                    parts = [parts, '\\'];
                                otherwise
                                    % Unknown escape, keep verbatim
                                    parts = [parts, esc];
                            end
                        end
                    elseif ch == quote
                        break;
                    else
                        parts = [parts, ch];
                    end
                end
                strv = parts;
            end

            % Parse Python-like array/list
            function arr = parseArray()
                nextc(); % consume '['
                elems = {};
                skipws();
                if peek() == ']'
                    nextc(); arr = {} ; return;
                end
                while true
                    skipws();
                    v = parseValue();
                    elems{end+1} = v; %#ok<AGROW>
                    skipws();
                    ch = peek();
                    if ch == ','
                        nextc(); continue;
                    elseif ch == ']'
                        nextc(); break;
                    else
                        % Unexpected character - try to continue or break
                        break;
                    end
                end
                % Attempt to convert to numeric array if possible
                isAllNumericScalar = all(cellfun(@(x) isnumeric(x) && isscalar(x), elems));
                if isAllNumericScalar
                    try
                        arr = cell2mat(elems);
                    catch
                        arr = elems;
                    end
                else
                    arr = elems;
                end
            end

            % Parse Python-like dict into MATLAB struct (sanitize field names)
            function obj = parseObject()
                nextc(); % consume '{'
                skipws();
                if peek() == '}'
                    nextc(); obj = struct(); return;
                end
                keys = {};
                vals = {};
                while true
                    skipws();
                    % Parse key: usually a quoted string, but allow barewords
                    if peek() == '''' || peek() == '"'
                        key = parseString();
                    else
                        key = parseToken();
                    end
                    skipws();
                    % Accept ':' or '=>' (just in case) or '='
                    if peek() == ':'
                        nextc();
                    elseif startsWith(s(idx:min(n, idx+1)), '=>')
                        idx = idx + 2;
                    elseif peek() == '='
                        nextc();
                    end
                    skipws();
                    v = parseValue();
                    keys{end+1} = key; %#ok<AGROW>
                    vals{end+1} = v; %#ok<AGROW>
                    skipws();
                    ch = peek();
                    if ch == ','
                        nextc(); continue;
                    elseif ch == '}'
                        nextc(); break;
                    else
                        % Unexpected - try to continue
                        break;
                    end
                end
                % Build struct, sanitize field names
                obj = struct();
                for ii = 1:length(keys)
                    rawKey = keys{ii};
                    if isempty(rawKey)
                        fname = sprintf('field_%d', ii);
                    else
                        fname = matlab.lang.makeValidName(rawKey);
                    end
                    % If field already exists, append numeric suffix to avoid overwriting
                    base = fname; kcount = 1;
                    while isfield(obj, fname)
                        fname = sprintf('%s_%d', base, kcount); kcount = kcount + 1;
                    end
                    obj.(fname) = vals{ii};
                end
            end

            % Final parse attempt
            try
                idx = 1; n = length(s);
                skipws();
                parsedValue = parseValue();
            catch ME
                warning('MATLAB:PythonSocketParseError', 'Failed to parse python string: %s. Returning raw string.', ME.message);
                parsedValue = pythonString;
            end
        end
    end
end
