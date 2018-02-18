%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Program Name : Custom driver for DS345 function generator               %
% Author       : Htoo Wai Htet                                            %
% Version      : 1.0                                                      %
% Description  : This is an object oriented program code that is used to  %
%                encapsulate the DS345 device as having only 4 variables: %
%                type of fucntion, amplitude, frequency and offset        % 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


classdef DS345Device

    %DS345Device
    %     This is the class for the DS345 Fuction Generator
    %     With basic control over the type, amplitude, freq, 
    %     and offset of the wave
    %Detailed explanation:
    %     Just a bunch of getters and setters for the four
    %     variables described above. All the functions take
    %     parameters as String so be sure to put '' around them 
    
    properties (SetAccess = private)
        device
        func
        amplitude
        frequency
        offset
    end
    
    methods
        % This is the constructor, if the function generator is connected
        % to COM5, you should use it as 
        % myDevice = DS345Device('COM5');
        function obj = DS345Device(com)
            % Check the arguements before passing to function
            obj.device = instrfind('Type', 'serial', 'Port', com, 'Tag', '');
            if isempty(obj.device)
                obj.device = serial(com);
            else
                fclose(obj.device);
                obj.device = obj.device(1);
            end
            fopen(obj.device);
 %           obj.reset();  %have the custom default setting
        end
        
        % An example usage would be:
        % myDevice.set_func('square');
        function set_func(obj, func)
            % Check the arguements before passing to function
            switch func
                case 'sine'
                    num = 0;
                case 'square'
                    num = 1;
                case 'triangle'
                    num = 2;
                case 'ramp'
                    num = 3;
                case 'noise'
                    num = 4;
                case 'arbitrary'
                    num = 5;
                otherwise
                    display('Choice Error. Defaulting to sine wave');
                    num = 0;
            end
            cmd = ['FUNC' char('0' + num)];
            fprintf(obj.device, cmd);
        end           
        
        % An example usage would be:
        % myDevice.set_amp('5', 'VP');
        function set_amp(obj, amp, unit)
            % Check the arguements before passing to function
            cmd = ['AMPL' amp unit];
            fprintf(obj.device, cmd);
        end
        
        % An example usage would be:
        % myDevice.set_freq('200');
        function set_freq(obj, freq)
            % Check the arguements before passing to function
            cmd = ['FREQ' freq];
            fprintf(obj.device, cmd);
        end
        
        % An example usage would be:
        % myDevice.set_offs('2.3');
        function set_offs(obj, offs)
            % Check the arguements before passing to function
            cmd = ['OFFS' offs];
            fprintf(obj.device, cmd);
        end
        
        % An example usage would be:
        % currentFunc = myDevice.func;
        function func = get.func(obj)
            num = str2double(query(obj.device, 'FUNC?'));
            switch num
                case 0
                    func = 'sine';
                case 1
                    func = 'square';
                case 2
                    func = 'triangle';
                case 3
                    func = 'ramp';
                case 4
                    func = 'noise';
                case 5
                    func = 'arbitrary';
                otherwise
                    func = 'error';
                    display(num);
            end
        end
        
        % An example usage would be:
        % currentAmp = myDevice.amp;
        function amp = get.amplitude(obj)
            amp = strtrim(query(obj.device, 'AMPL? VP'));
        end
        
        % An example usage would be:
        % currentFreq = myDevice.freq;
        function freq = get.frequency(obj)
            freq = strtrim(query(obj.device, 'FREQ?'));
        end
        
        % An example usage would be:
        % currentOffset = myDevice.offs;
        function offs = get.offset(obj)
            offs = strtrim(query(obj.device, 'OFFS?'));
        end
                
        % An example usage would be:
        % myDevice.reset();
        function reset(obj)
            fprintf(obj.device, '*RST');
        end
        
        % An example usage would be:
        % myDevice.delete();
        function delete(obj)
            % Disconnect all objects.
            fclose(obj.device);
            % Clean up all objects.
            delete(obj.device);
        end
    end
end

