classdef RedBlueSine < edu.washington.riekelab.protocols.RiekeLabProtocol
    %sine test code
    
    properties
        useRandomSeed = true
        preTime = 100
        stimTime = 1000
        tailTime = 100
        period = 0.5
        led1
        Amp1 = 0.05
        lightMean1 = 1
        led2
        Amp2 = 0.05
        lightMean2 = 1
        phaseShift = 0
        amp
        ampHoldSignal = -60
        numberOfAverages = uint16(5)    % Number of epochs
        interpulseInterval = 0          % Duration between pulses (s)
    end
    
    properties (Hidden)
        led1Type
        led2Type
        ampType
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led1, obj.led1Type] = obj.createDeviceNamesProperty('LED');
            [obj.led2, obj.led2Type] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
            
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()createPreviewStimuli(obj));
            function s = createPreviewStimuli(obj)
                numPulses = 1;
                s = cell(numPulses*2, 1);
                for i = 1:numPulses
                    [s{2*i-1}, s{2*i}] = obj.createLedStimulus(i);
                end
            end
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp), 'GroupBy',{'PlotGroup'});
            obj.showFigure('symphonyui.builtin.figures.ResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, ...
                'baselineRegion', [0 obj.preTime], ...
                'measurementRegion', [obj.preTime obj.preTime+obj.stimTime]);

            device1 = obj.rig.getDevice(obj.led1);
            device1.background = symphonyui.core.Measurement(obj.lightMean1, device1.background.displayUnits);
            device2 = obj.rig.getDevice(obj.led2);
            device2.background = symphonyui.core.Measurement(obj.lightMean2, device2.background.displayUnits);
        end
        
        function [stim1, stim2] = createLedStimulus(obj, pulseNum)
            gen = symphonyui.builtin.stimuli.SineGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.period = obj.period;
            gen.phase = 0;
            gen.mean = obj.lightMean1;
            gen.sampleRate = obj.sampleRate;
            gen.units = 'V';

            gen.amplitude = obj.Amp1;
            if (rem(pulseNum, 3) == 2)
                gen.amplitude = 0;
            end
            
            stim1 = gen.generate();

            gen.mean = obj.lightMean2;
            gen.phase = obj.phaseShift;
            gen.amplitude = obj.Amp2;
            if (rem(pulseNum, 3) == 1)
                gen.amplitude = 0;
            end
   
            stim2 = gen.generate();
     
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
             % Add LED stimulus.
            [stim1, stim2] = obj.createLedStimulus(obj.numEpochsPrepared);
            cnt = rem(obj.numEpochsPrepared, 3);
            epoch.addParameter('PlotGroup', cnt);
            
            epoch.addStimulus(obj.rig.getDevice(obj.led1), stim1);
            epoch.addStimulus(obj.rig.getDevice(obj.led2), stim2);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led1);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
       
        
    end
    
end

