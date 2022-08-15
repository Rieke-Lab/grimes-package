classdef DriftingGrating < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    % todo:
    %   - cone iso and color
    
    properties
        preTime = 500 % ms
        stimTime = 1000 % ms
        tailTime = 1000 % ms
        spatialPeriod = 300             % period of spatial grating (um)
        temporalPeriod = 500            % temporal period (ms)
        apertureDiameter = 80               % aperture diameter (um)
        contrasts = [0.1 0.2 0.4]       % Grating contrasts [0, 1]
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        numberOfAverages = uint16(5)   % Number of epochs at each contrast
        amp                             % Output amplifier
        psth = false;                   % Toggle psth in mean response figure
    end
    
    properties (Hidden)
        ampType
        contrast
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
            if length(obj.contrasts) > 1
                colors = edu.washington.riekelab.turner.utils.pmkmp(length(obj.contrasts),'CubicYF');
            else
                colors = [0 0 0];
            end
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp), ...
                    'groupBy', {'contrast'},'sweepColor',colors,'psth', obj.psth);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
        end
        
        function p = createPresentation(obj)

            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            spatialPeriodPix = obj.rig.getDevice('Stage').um2pix(obj.spatialPeriod);
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the grating stimulus.
            grating = stage.builtin.stimuli.Grating();
            grating.position = canvasSize / 2;
            grating.size = [apertureDiameterPix, apertureDiameterPix];
            grating.spatialFreq = 1/spatialPeriodPix; 
            grating.color = 2*obj.backgroundIntensity;
            
            % Create a controller to change the grating's phase property as a function of time. 
            gratingPhaseController = stage.builtin.controllers.PropertyController(grating, 'phase', @(state)state.time * 360 / (obj.temporalPeriod * 1e-3));
            gratingContrastController = stage.builtin.controllers.PropertyController(grating, 'contrast',...
                        @(state)getGratingContrast(obj, state.time));

            % Add the stimulus and controller.
            p.addStimulus(grating);
            p.addController(gratingPhaseController);
            p.addController(gratingContrastController);

            aperture = stage.builtin.stimuli.Rectangle();
            aperture.position = canvasSize/2;
            aperture.size = [apertureDiameterPix, apertureDiameterPix];
            mask = stage.core.Mask.createCircularAperture(1, 1024); %circular aperture
            aperture.setMask(mask);
            p.addStimulus(aperture); %add aperture
            aperture.color = obj.backgroundIntensity;
             
            function c = getGratingContrast(obj, time)
                c = obj.contrast;
                if (time < (obj.preTime*1e-3))
                    c = 0;
                end
                if (time > ((obj.preTime + obj.stimTime)/1e3))
                    c = 0;
                end
            end
        end

        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if ((obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < (obj.numberOfAverages * length(obj.contrasts))) && ...
                    (mod(obj.numEpochsCompleted, obj.numberOfAverages) ~= 0))
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
            end
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            device = obj.rig.getDevice(obj.amp);
            duration = obj.stimTime * 1e-3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);

            indx = floor(double(obj.numEpochsCompleted)/double(obj.numberOfAverages))+1;
            
            if (indx > length(obj.contrasts))
                fprintf(1, 'error in setting contrast\n');
                indx = length(obj.contrasts);
            end
            
            obj.contrast = obj.contrasts(indx);
            epoch.addParameter('contrast', obj.contrast);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < (obj.numberOfAverages * length(obj.contrasts));
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < (obj.numberOfAverages * length(obj.contrasts));
        end
    end
end