classdef ConeLinearizationGratingsTest < edu.washington.riekelab.protocols.RiekeLabStageProtocol
    
    properties
        stimulusDataPath = 'stimulus file'; % string of path to
        isomerizationsAtMonitorValue1 = 0;
        inputStimulusFrameRate = 60;
        preFrames = 30
        postFrames = 30
        barWidth = [5 10 20 40 80 160] % um
        rotation = 0; % degrees
        apertureDiameter = 0; % um
        onlineAnalysis = 'none';
        averagesPerStimulus = uint16(20);
        amp
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        currentStimuli
        stimulusDurationSeconds
        backgroundIsomerizations
        meanIntensity
        ResourceFolderPath = 'C:\Users\Public\Documents\rieke-package\+edu\+washington\+riekelab\+rieke\+resources\'
        stimuli
        currentBarWidth
        grateMatrix
    end
    
    properties (Hidden, Transient)
        analysisFigure
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function constructStimuli(obj)
            obj.stimuli = struct;
            obj.stimuli.names = {'original', 'modified'};
            
            stimulusData = load(strcat(obj.ResourceFolderPath, obj.stimulusDataPath));
            
            obj.backgroundIsomerizations = stimulusData.positiveOriginal(1);
            obj.meanIntensity = obj.backgroundIsomerizations / obj.isomerizationsAtMonitorValue1;
            
            obj.stimuli.lookup = containers.Map(obj.stimuli.names, ...
                {{stimulusData.positiveOriginal, stimulusData.negativeOriginal}, ...
                {stimulusData.positiveModified, stimulusData.negativeModified}});
            
            obj.stimulusDurationSeconds = (obj.preFrames + numel(stimulusData.positiveOriginal) + obj.postFrames) ...
                / obj.inputStimulusFrameRate;
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            obj.constructStimuli();
            
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                'groupBy',{'stimulus type'},...
                'sweepColor',[0 0 0]);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        end
                
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            apertureDiameterPix =obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            p = stage.core.Presentation(obj.stimulusDurationSeconds); %create presentation of specified duration
            p.setBackgroundColor(obj.meanIntensity); % Set background intensity
            
            startMatrix=uint8((1+obj.grateMatrix)*obj.meanIntensity*255);
            grate=stage.builtin.stimuli.Image(startMatrix);
            grate.size = [apertureDiameterPix, apertureDiameterPix];
            grate.position=canvasSize/2;
            % Use linear interpolation when scaling the image.
            grate.setMinFunction(GL.LINEAR);
            grate.setMagFunction(GL.LINEAR);
            p.addStimulus(grate);

            if  (obj.apertureDiameter > 0) % Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.meanIntensity;
                aperture.size = [apertureDiameterPix, apertureDiameterPix];
                mask = stage.core.Mask.createCircularAperture(1, 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
                
            imageController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame));
            p.addController(imageController); %add the controller
                     
            function i = getNewImage(obj, frame)
                 i = uint8((ones(size(obj.grateMatrix))*obj.meanIntensity*255));
                 if (frame >= obj.preFrames && frame < (obj.preFrames + length(obj.currentStimuli{1})))
                     grateMatrix = obj.grateMatrix;
                     indices = find(obj.grateMatrix(:) > 0);
                     grateMatrix(indices) = obj.currentStimuli{1}(frame-obj.preFrames+1);
                     indices = find(obj.grateMatrix(:) < 0);
                     grateMatrix(indices) = obj.currentStimuli{2}(frame-obj.preFrames+1);
                     i = uint8(grateMatrix*255);
                 end
            end
            
        end
        
        function prepareEpoch(obj, epoch)
            apertureDiameterPix =obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, epoch);
            
            index = mod(obj.numEpochsCompleted, numel(obj.stimuli.names)) + 1;
            
            obj.currentStimuli = obj.stimuli.lookup(obj.stimuli.names{index});
            obj.currentStimuli{1} = obj.currentStimuli{1} / obj.isomerizationsAtMonitorValue1;
            obj.currentStimuli{2} = obj.currentStimuli{2} / obj.isomerizationsAtMonitorValue1;
            epoch.addParameter('stimulus type', obj.stimuli.names{index});            

            index = floor(mod(obj.numEpochsCompleted, numel(obj.barWidth) * numel(obj.stimuli.names))/numel(obj.stimuli.names)) + 1;
            obj.currentBarWidth = obj.barWidth(index);
            currentBarWidthPix=ceil(obj.rig.getDevice('Stage').um2pix(obj.currentBarWidth));
            
            epoch.addParameter('currentBarWidth', obj.currentBarWidth);
            
            ampDevice = obj.rig.getDevice(obj.amp);
            duration = obj.stimulusDurationSeconds;
            epoch.addDirectCurrentStimulus(ampDevice, ampDevice.background, duration, obj.sampleRate);
            epoch.addResponse(ampDevice);
            
            x =pi*meshgrid(linspace(-apertureDiameterPix/2,apertureDiameterPix/2,apertureDiameterPix));
            grate2D =sin(x/currentBarWidthPix);
            grate2D(grate2D>0)=1;
            grate2D(grate2D<=0)=-1;
            obj.grateMatrix = grate2D;
                        
        end
                
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.averagesPerStimulus * numel(obj.stimuli.names) * numel(obj.barWidth);
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.averagesPerStimulus * numel(obj.stimuli.names) * numel(obj.barWidth);
        end
    end
end
