classdef LedPulseSequence < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents a set of rectangular pulse stimuli to a specified LED and records from a specified amplifier.
    
    properties
        led                             % Output LED
        preTime = 500                    % Pulse leading duration (ms)
        stimTime = [10 20]                  % Pulse duration (ms)
        tailTime = 500                  % Pulse trailing duration (ms)
        lightAmplitude = [0.2 0.3 0.5]            % Pulse amplitudes (V or norm. [0-1] depending on LED units)
        lightMean = 0                   % Pulse and LED background mean (V or norm. [0-1] depending on LED units)
        amp                             % Input amplifier
        psth = true;                    % Toggle psth in mean response figure
        fixedFlux = true;               % hold photon flux fixed for different durations (min dur * amp)
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        numberOfAverages = uint16(5)    % Number of epochs
        interpulseInterval = 0          % Duration between pulses (s)
    end
    
    properties (Hidden)
        ledType
        ampType
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()obj.createLedStimulus());
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp),'psth',obj.psth,'groupBy', {'currentAmplitude','currentStimTime'});
                obj.showFigure('symphonyui.builtin.figures.ResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, ...
                    'baselineRegion', [0 obj.preTime], ...
                    'measurementRegion', [obj.preTime obj.preTime+obj.tailTime]);
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, obj.rig.getDevice(obj.amp2), {@mean, @var}, ...
                    'baselineRegion1', [0 obj.preTime], ...
                    'measurementRegion1', [obj.preTime obj.preTime+obj.tailTime], ...
                    'baselineRegion2', [0 obj.preTime], ...
                    'measurementRegion2', [obj.preTime obj.preTime+obj.tailTime]);
            end
            
            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(obj.lightMean, device.background.displayUnits);
        end
        
        function [stim, currentAmplitude, currentStimTime] = createLedStimulus(obj)
            currentAmplitude = obj.lightAmplitude(randi([1 length(obj.lightAmplitude)]));
            currentStimTime = obj.stimTime(randi([1 length(obj.stimTime)]));
            
            if (obj.fixedFlux)
                currentAmplitude = currentAmplitude * min(obj.stimTime) / currentStimTime;
            end
                        
            gen = symphonyui.builtin.stimuli.PulseGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = currentStimTime;
            gen.tailTime = obj.tailTime;
            gen.amplitude = currentAmplitude;
            gen.mean = obj.lightMean;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);

            [stim, currentAmplitude, currentStimTime] = obj.createLedStimulus();
            
            epoch.addParameter('currentAmplitude', currentAmplitude);
            epoch.addParameter('currentStimTime', currentStimTime);
            
            epoch.addStimulus(obj.rig.getDevice(obj.led), stim);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end
        
    end
    
end

