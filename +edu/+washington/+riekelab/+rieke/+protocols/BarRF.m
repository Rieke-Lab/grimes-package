classdef BarRF < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Spot leading duration (ms)
        stimTime = 2000                 % Spot duration (ms)
        tailTime = 1000                 % Spot trailing duration (ms)
        contrast = 0.5                  % Bar contrast (0-1)
        temporalFrequency = 2.0         % Modulation frequency (Hz)
        barSize = [50 1000]             % Bar size [width, height] (um)
        orientation = 0                 % Bar orientation (degrees)
        temporalClass = 'squarewave'    % Squarewave or pulse?
        positions = [-300 -200 -100 0 100 200 300];         % Bar center position (um)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        colorWeights = [1 1 1]          % weights of r, g, b leds
        onlineAnalysis = 'extracellular'         % Online analysis type.
    end
    
    properties (Hidden)
        ampType
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'squarewave', 'pulse'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc'})
        position
        sequence
        bkg
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'position'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
                        
            % Convert from um to pix
            obj.sequence = obj.rig.getDevice('Stage').um2pix(obj.positions);
                                    
            
            obj.bkg = obj.backgroundIntensity;
        end
               
        function p = createPresentation(obj)

            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            rect = stage.builtin.stimuli.Rectangle();
            rect.size = obj.rig.getDevice('Stage').um2pix(obj.barSize); % um -> pix
            rect.orientation = obj.orientation;
            rect.position = canvasSize/2 + obj.position;
            
            rect.color = obj.colorWeights * (obj.contrast*obj.bkg + obj.bkg);
            
            % Add the stimulus to the presentation.
            p.addStimulus(rect);       
            
            % Control when the spot is visible.
            spotVisible = stage.builtin.controllers.PropertyController(rect, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
            
            % Control the bar intensity.
            if strcmp(obj.temporalClass, 'squarewave')
                colorController = stage.builtin.controllers.PropertyController(rect, 'color', ...
                    @(state)getSpotColorVideoSqwv(obj, state.time - obj.preTime * 1e-3));
                p.addController(colorController);
            end
            
            function c = getSpotColorVideoSqwv(obj, time)       
                c = obj.contrast * sign(sin(obj.temporalFrequency*time*2*pi)) * obj.colorWeights * obj.bkg + obj.bkg;
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);

            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
            
            obj.position = obj.sequence(obj.numEpochsCompleted+1);
            epoch.addParameter('position', obj.position);
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < length(obj.positions);
        end

        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < length(obj.positions);
        end
    end
end