classdef Switch < handle
    % Switch class for handling power switch operations
    properties (Constant)
        ON = 1;  % Constant for switch ON state
        OFF = 0; % Constant for switch OFF state
    end
    % Static properties
    properties (Access=public)
        python = nan;   % Placeholder for Python object
        id = 0;         % Power Device ID. Default is 0

    end

    methods (Access=public)
        % Constructor
        function obj = Switch(varargin)
            % Constructor
            if nargin == 0
               % Initialize python server
                try
                    python = interface.Python();
                    python.serve(1);        % Start the Python server in background
                    python.connect();       % Connect to the Python server
                    obj.python = python;    % Store the Python object
                catch ME
                    error('Failed to initialize Python object: %s', ME.message);
                end
            elseif nargin == 1
                obj.python = varargin{1};               
            elseif nargin >= 2
                obj.python = varargin{1};  
                obj.id = varargin{2};
            end
            % Setup Python 
            obj.python.exec('from hdd.power import Switch');
            obj.python.exec(sprintf('switch = Switch(%d)', obj.id));
            obj.python.eval('switch.init()');            
        end
        % Switch state
        function curState = state(self, varargin)
            if nargin <= 1 
                % Read the state
                self.python.exec('state = switch.state()');  
                curState =  self.python.get('state');
                if ~nargout
                    if curState 
                        fprintf('HDD Power Supply turned ON. \n');
                    else
                        fprintf('HDD Power Supply turned OFF. \n');                        
                    end
                end

            else
                curState = varargin{1};
                self.python.eval(sprintf('switch.state(%d)', curState));                
            end
        end

        % Destructor
        function delete(obj)
            % Clean up the Python object when the Switch object is deleted
            try
                obj.python.close();  % Close the Python connection
            catch ME
                warning(ME.identifier, 'Failed to close Python connection: %s', ME.message);
            end
        end
    end


    methods (Static)
        function state = toggle(state)
            % Toggle the switch state
            if state == Switch.ON
                state = Switch.OFF;
            else
                state = Switch.ON;
            end
        end

        function isOn = isOn(state)
            % Check if the switch is ON
            isOn = (state == Switch.ON);
        end

        function isOff = isOff(state)
            % Check if the switch is OFF
            isOff = (state == Switch.OFF);
        end
    end
end