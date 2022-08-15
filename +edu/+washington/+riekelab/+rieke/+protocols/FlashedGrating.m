classdef FlashedGrating < edu.washington.riekelab.protocols.RiekeLabStageProtocol

    properties
        preTime = 200 % ms
        stimTime = 200 % ms
        tailTime = 200 % ms
        
        apertureDiameter = 200 % um

        gratingContrast = 0.5; %as a fraction of background intensity
        barWidth = [5 10 20 40 80 160] % um
        backgroundIntensity = 0.5; %0-1
        randomizeOrder = false;
       
        onlineAnalysis = 'none'
        amp % Output amplifier
        numberOfAverages = uint16(90) % 6 x noMeans x noAvg
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        barWidthSequence
        currentBarWidth
        gratePhaseShift
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
                'groupBy',{'currentBarWidth'});
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
            
%             if ~strcmp(obj.onlineAnalysis,'none')
%             responseDimensions = [2, 3, length(obj.gratingMean)]; %image/equiv by surround contrast by grating mean (1)
%             obj.showFigure('edu.washington.riekelab.turner.figures.ModImageVsIntensityFigure',...
%             obj.rig.getDevice(obj.amp),responseDimensions,...
%             'recordingType',obj.onlineAnalysis,...
%             'preTime',obj.preTime,'stimTime',obj.stimTime,...
%             'stimType','gratingCorrSurround');
%             end
            % Create bar width sequence.
            obj.barWidthSequence = obj.barWidth;

        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
                              
            index = mod(obj.numEpochsCompleted, length(obj.barWidthSequence)) + 1;
            % Randomize the bar width sequence order at the beginning of each sequence.
            if index == 1 && obj.randomizeOrder
                obj.barWidthSequence = randsample(obj.barWidthSequence, length(obj.barWidthSequence));
            end
            obj.currentBarWidth = obj.barWidthSequence(index);
            
            if (rem(floor(obj.numEpochsCompleted / length(obj.barWidthSequence)), 2) == 0)
                obj.gratePhaseShift = 0;
            else
                obj.gratePhaseShift = 180;
            end
            % bar greater than 1/2 aperture size -> just split field grating.
            % Allows grating texture to be the size of the aperture and the
            % resulting stimulus is the same...
            if (obj.currentBarWidth > obj.apertureDiameter/2);
                obj.currentBarWidth = obj.apertureDiameter/2;
            end
            epoch.addParameter('currentBarWidth', obj.currentBarWidth);

        end
        
        function p = createPresentation(obj)            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            currentBarWidthPix = obj.rig.getDevice('Stage').um2pix(obj.currentBarWidth);

            grate = edu.washington.riekelab.turner.stimuli.GratingWithOffset('square'); %square wave grating
            grate.orientation = 0;
            grate.size = [apertureDiameterPix, apertureDiameterPix];
            grate.position = canvasSize/2;
            grate.spatialFreq = 1/(2*currentBarWidthPix); %convert from bar width to spatial freq
            grate.meanLuminance = obj.backgroundIntensity;
            grate.amplitude = obj.gratingContrast * obj.backgroundIntensity;
            %calc to apply phase shift s.t. a contrast-reversing boundary
            %is in the center regardless of spatial frequency. Arbitrarily
            %say boundary should be positve to right and negative to left
            %crosses x axis from neg to pos every period from 0
            zeroCrossings = 0:(grate.spatialFreq^-1):grate.size(1); 
            offsets = zeroCrossings-grate.size(1)/2; %difference between each zero crossing and center of texture, pixels
            [shiftPix, ~] = min(offsets(offsets>0)); %positive shift in pixels
            phaseShift_rad = (shiftPix/(grate.spatialFreq^-1))*(2*pi); %phaseshift in radians
            phaseShift = 360*(phaseShift_rad)/(2*pi); %phaseshift in degrees
            grate.phase = phaseShift + obj.gratePhaseShift; %keep contrast reversing boundary in center
            p.addStimulus(grate);
                
            %hide during pre & post
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color =obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
                   
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

    end
    
end