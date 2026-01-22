classdef pythonobject < dynamicprops
    %PYTHONPROXY Simple concrete dynamicprops subclass used as a container for mirrored methods.
    %   Instances of this class can have properties added at runtime via addprop.

    % No additional code needed; this class exists so we can instantiate
    % a non-abstract dynamicprops-derived object.
    properties
        name;               % Name of the object
        client;             % MATLAB client which connect to Python
        attributes = {};    % To store Python attributes of the objects
    end    
    methods
        function self = pythonobject(client)
            self.name = '';
            self.client = client;
        end
        function varargout = subsref(self, S)
            % S(1).type is the access type (e.g., '.')
            % S(1).subs is the property/method name (e.g., 'myProperty')

            attrName = S(1).subs;

            if ismember(attrName, self.attributes)
                [varargout{1:nargout}] =  self.client.eval(sprintf('%s.%s', self.name, char(attrName)));
            else
                [varargout{1:nargout}] = builtin('subsref', self, S);    
            end
        end       

        % New: Forwarded assignment to Python attributes
        function self = subsasgn(self, S, value)
            attrName = S(1).subs;
            if ismember(attrName, self.attributes)
                self.client.set(sprintf('%s.%s', self.name, char(attrName)), value);
            end
            self = builtin('subsasgn', self, S, value);
        end
    end
end
