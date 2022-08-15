classdef DriftingGabor < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    % todo:
    %   - cone iso and color
    
    properties
        stimTime = 660 % ms
        spatialPeriod = 300             % period of spatial grating (um)
        temporalPeriod = 500            % temporal period (ms)
        gaborStanDev = 80               % standard deviation of Gaussian envelope (um)
        contrasts = [0.1 0.2 0.4]   % Grating contrasts [0, 1]
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
            
            % custom figure handler
            if isempty(obj.analysisFigure) || ~isvalid(obj.analysisFigure)
                obj.analysisFigure = obj.showFigure('symphonyui.builtin.figures.CustomFigure', @obj.DriftingGaborAnalysis);
                f = obj.analysisFigure.getFigureHandle();
                set(f, 'Name', 'GaborAnalysis');
                obj.analysisFigure.userData.trialCounts = zeros(size(obj.contrasts));
                obj.analysisFigure.userData.F1 = zeros(size(obj.contrasts));
                obj.analysisFigure.userData.axesHandle = axes('Parent', f);
            else
                obj.analysisFigure.userData.trialCounts = zeros(size(obj.contrasts));
                obj.analysisFigure.userData.F1 = zeros(size(obj.contrasts));
            end

        end

        function DriftingGaborAnalysis(obj, ~, epoch) %online analysis function
            response = epoch.getResponse(obj.rig.getDevice(obj.amp));
            epochResponseTrace = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            axesHandle = obj.analysisFigure.userData.axesHandle;
            trialCounts = obj.analysisFigure.userData.trialCounts;
            F1 = obj.analysisFigure.userData.F1;
             
            if (obj.psth == true) %spike recording
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace(round((sampleRate*obj.stimTime*1e-3/4)+1):floor((sampleRate*(obj.stimTime*1e-3*3/4))));
                %count spikes
                S = edu.washington.riekelab.turner.utils.spikeDetectorOnline(epochResponseTrace);
                epochResponseTrace = zeros(size(epochResponseTrace));
                epochResponseTrace(S.sp) = 1; %spike binary
                
            else %intracellular - Vclamp
                epochResponseTrace = epochResponseTrace-mean(epochResponseTrace(1:floor(sampleRate*obj.stimTime*1e-3/4))); %baseline
                %take (prePts+1:prePts+stimPts)
                epochResponseTrace = epochResponseTrace(round((sampleRate*obj.stimTime*1e-3/4)+1):floor((sampleRate*(obj.stimTime*1e-3*3/4))));
            end

            L = length(epochResponseTrace); %length of signal, datapoints
            X = abs(fft(epochResponseTrace));
            X = X(1:L/2);
            f = sampleRate*(0:L/2-1)/L; %freq - hz
            [~, F1ind] = min(abs(f-1./obj.temporalPeriod)); %find index of F1 frequencies

            F1power = 2*X(F1ind); %pA^2/Hz for current rec, (spikes/sec)^2/Hz for spike rate
            
            contrastIndex = find(obj.contrast == obj.contrasts);
            trialCounts(contrastIndex) = trialCounts(contrastIndex) + 1;
            F1(contrastIndex) = F1(contrastIndex) + F1power;
            
            cla(axesHandle);
            h1 = line(obj.contrasts, F1./trialCounts, 'Parent', axesHandle);
            set(h1,'Color','g','LineWidth',2,'Marker','o');
            xlabel(axesHandle,'contrast')
            ylabel(axesHandle,'amplitude')

            obj.analysisFigure.userData.trialCounts = trialCounts;
            obj.analysisFigure.userData.F1 = F1;
        end
        
        function p = createPresentation(obj)

            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            spatialPeriodPix = obj.rig.getDevice('Stage').um2pix(obj.spatialPeriod);
            gaborStanDevPix = obj.rig.getDevice('Stage').um2pix(obj.gaborStanDev);
            
            p = stage.core.Presentation(obj.stimTime * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create the grating stimulus.
            grating = stage.builtin.stimuli.Grating();
            grating.position = canvasSize / 2;
            grating.size = [gaborStanDevPix*4, gaborStanDevPix*4];
            grating.spatialFreq = 1/spatialPeriodPix; 
            grating.color = 2*obj.backgroundIntensity;
            
            % Create a controller to change the grating's phase property as a function of time. 
            gaborPhaseController = stage.builtin.controllers.PropertyController(grating, 'phase', @(state)state.time * 360 / (obj.temporalPeriod * 1e-3));
            gaborContrastController = stage.builtin.controllers.PropertyController(grating, 'contrast',...
                        @(state)getGaborContrast(obj, state.time));

            % Add the stimulus and controller.
            p.addStimulus(grating);
            p.addController(gaborPhaseController);
            p.addController(gaborContrastController);

            % Assign a gaussian envelope mask to the grating.
            mask = stage.core.Mask.createGaussianEnvelope(gaborStanDevPix*2);
            grating.setMask(mask);
            
            function c = getGaborContrast(obj, time)
                c = obj.contrast;
                if (time < obj.stimTime*1e-3/4)
                    c = obj.contrast * time/(obj.stimTime*1e-3/4);
                end
                if (time > obj.stimTime*1e-3*3 / 4)
                    c = obj.contrast * (obj.stimTime*1e-3 - time)/(obj.stimTime*1e-3/4);
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