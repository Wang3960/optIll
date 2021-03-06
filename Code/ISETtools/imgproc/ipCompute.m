function vci = ipCompute(vci,sensor)
% Image processing pipeline from image sensor to a display
%
%    ip = ipCompute(ip,sensor);
%
% The image pipeline (ip) converts  sensor data (sensor) into an image. 
%
% The ip slot 
%  'input'  contains the voltage (or dv) data from the sensor object.
%  'result' contains the computed image. 
%
% By default, this routine applies demosaic, sensor color conversion to an
% internal representation, and illuminant correction towards a specific
% display (in that order).
%
% If the sensor is monochrome, the pipeline copies the sensor data to the
% display output as a monochrome image.
%
% This method runs on the assumption that the internal color space is
% three-dimensional.
%
% We are writing other rendering pipelines based on different architectures
% in the future.
%
% If the ip name begins with 'L3' then the data are rendered using the L3
% render method. The option 'L3global' uses the global parameters of the L3
% structure.  In this case, we expect an L3 structure that was learned is
% attached to the ip.
%
% Copyright ImagEval Consultants, LLC, 2003.


%% Check arguments
if ieNotDefined('vci'), error('Image process structure is required.'); end
if ieNotDefined('sensor'), error('Sensor structure is required.'); end


%% Assign a name if the current one is 'default' or a copy.  
% Maybe we should always assign the sensor name whenever we compute?
if strcmpi(ipGet(vci,'name'),'default') || ... 
    strcmpi(ipGet(vci,'name'),'copy')
    vci = ipSet(vci,'name',sensorGet(sensor(1),'name'));
end

%% Handle sensor array case.  No special exposure cases are handled.
if length(sensor) > 1
    % No need to put volts into the vci.  Demosaic will recognize this as
    % an array of sensors and it will pull the volts out of each of the
    % individual sensors.
    vci = ipSet(vci,'datamax',sensorGet(sensor(1),'max'));
    vci = vciComputeSingle(vci,sensor);
    return;
end

%% Classic CFA mosaic. Get the sensor data.

% We demosaick the quantized sensor values.  If this field is empty, use the
% continuous voltages 
vci = ipSet(vci,'input',sensorGet(sensor,'dv or volts'));

%  The max is either the max digital value or the voltage swing, depending
%  on whether we have computed DVs or Volts.  But this value is not
%  terribly important because the we render into an RGB display in the unit
%  cube.
vci = ipSet(vci,'datamax',sensorGet(sensor(1),'max'));

%% Pre-process the multiple exposure durations case
% Combine the the exposure durations into a single planar array.  Then we
% process using the single exposure processing stream.

exposureMethod = sensorGet(sensor,'exposure method');
switch exposureMethod(1:3)
    case 'sin'  % singleExposure
        % Don't need to pre-process
    case 'bra'  % bracketedExposure
        % On return, the maximum sensible exposure time is set
        vci = vciComputeBracketed(vci,sensor);
    case 'cfa'  % cfaExposure
        vci = vciComputeCFA(vci,sensor);
    otherwise
        error('Unknown exposure method %s\n',exposureMethod);
end

% We introduce the L3 pipeline here, which is not part of ISET.
% Perhaps we should test for the L3render function and warn the user if it
% does not exist on the path?
pType = ieParamFormat(ipGet(vci,'name'));
if strncmpi(pType,'l3',2)
    
    %Perform L^3 processing, either local or global
    mode = 'local';
    if strncmpi(pType,'l3global',8), mode = 'global'; end
    fprintf('** Using L3render %s method **\n',mode);
    
    L3 = ipGet(vci,'L3');
    [L3xyz,lumIdx,satIdx,clusterIdx] = L3render(L3,sensor,mode);

    % Convert the results and save in the L3 structure and vci.
    % Shouldn't we be saving the srgb?  Or using xyz2lrgb?
    [srgb, lrgb] = xyz2srgb(L3xyz); %#ok<ASGLU>
    vci = ipSet(vci,'result',lrgb);
    
    L3  = L3Set(L3,'luminance index',lumIdx);
    L3  = L3Set(L3,'xyz result',L3xyz);
    L3  = L3Set(L3,'saturation index',satIdx);
    L3  = L3Set(L3,'cluster index',clusterIdx);
    vci = ipSet(vci,'L3',L3);
else
    % Conventional RGB pipeline, most common case
    vci = vciComputeSingle(vci,sensor);
end

return


function vci = vciComputeSingle(vci,sensor)
% Process image for single exposure case, or after pre-processing for
% bracketed and CFA cases.
%
%    vci = vciComputeSingle(vci,sensor)
%
% The processing steps through
%   1. Demosaicing
%   2. Sensor correction to ICS
%   3. Illuminant correction in ICS
%   4. Display rendering
%
% Steps 2-4 are often a linear transform. The transform is scaled so that
% the image output maximum matches the ratio of the maximum sensor data
% value to the saturation level of the sensor.
%

% We handle the case of different number of filters somewhat differently.
nFilters = sensorGet(sensor(1),'nfilters');
nSensors = length(sensor);

if nFilters == 1 && nSensors == 1
    % If monochrome sensor, just copy the sensor values to the RGB values
    % of the display, but normalize between 0 and 1 based on the kind of
    % data.
    img = vci.data.input / sensorGet(sensor,'max');
    
    % The image data are RGB, even though the sensor is monochrome.
    vci = ipSet(vci,'result',repmat(img,[1,1,3]));
    return;

elseif nFilters == 2
    warndlg('Rendering pipeline not implemented for 2 color sensor data.');
    
    % Null data.  I wonder if we should aim for Edwin Land type stuff here.
    vci = ipSet(vci,'result',[]);
    return;
    
elseif nFilters >= 3 || nSensors > 1
    % Basic color processing pipeline. Single exposure case.
    %
 
    %1.  Demosaic in sensor space. The data remain in the sensor
    % channels and there is no scaling.
    if ndims(vci.data.input) == nFilters, img = vci.data.input;
    elseif ismatrix(vci.data.input),      img = Demosaic(vci,sensor);
    else
        error('Not sure about input data structure');
    end
    
    % Save the demosaiced sensor space channel values. May be used later
    % for adaptation of color balance for IR enabled sensors
    vci = ipSet(vci,'sensor space',img);

    % Decide if we are using the current matrix or we are in a processing
    % chain for balancing and rendering, or whether we are using the
    % current matrix.
    tMethod = ieParamFormat(ipGet(vci,'transform method'));
    switch tMethod
        case 'current'
            % Use the stored transform matrix, don't recompute.
            T   = ipGet(vci,'prodT');
            img = imageLinearTransform(img,T);

        case {'new','manual matrix entry'}
            % Allow the user to specify a matrix from the GUI. When set this
            % way, the sensor correction transform is the only one used to
            % convert from sensor to display.

            Torig = ipGet(vci,'combined transform');
            Torig = Torig/max(Torig(:));
            T = ieReadMatrix(Torig,'%.3f   ','Color Transform');
            if isempty(T), return; end

            % Store and apply this transform.
            vci = ipSet(vci,'conversion matrix sensor',T);
            img = imageLinearTransform(img,T);  % vcNewGraphWin; imagesc(img)

            % Set the other transforms to empty.
            vci = ipSet(vci,'correction matrix illuminant',[]);
            % vci = ipSet(vci,'sensor correction transform',[]);
            vci = ipSet(vci,'ics2display',[]);
        case 'adaptive'

            % Recompute a transform based, in part, on process the image
            % data and with knowledge of the multiple color filters.  
            %
            
            % 2.  Convert the demosaicked img data into an internal color
            % space. The choice of the internal space is governed by the
            % field ipGet(vci,'Sensor Correction Method')
            
            N = length(sensor);
            if N > 1
                % If the sensor is an array of monochrome sensors, we
                % create a dummy version of the sensor,  that includes all
                % of the filters. These are needed for
                % imageSensorCorrection and displayRender (below).
                s = sensor(1);
                filterSpectra = zeros(sensorGet(s,'n wave'),N);
                for ii=1:N
                    filterSpectra(:,ii) = sensorGet(sensor(ii),'filter spectra');
                end    
                s = sensorSet(s,'filter spectra',filterSpectra);
            else
                s = sensor;
            end
    
            [img,vci] = imageSensorCorrection(img,vci,s);
            if isempty(img), disp('User canceled'); return; end
            % imtool(img/max(img(:))); ii = 3; imtool(img(:,:,ii))
            
            % 3. Perform an illuminant correct operation in the ICS space.
            % The operation is governed by the 'illuminant correction method'
            % parameter.
            [img,vci] = imageIlluminantCorrection(img,vci);

            % 4.  Convert from the img data in the internal color space
            % into display space.  The display space is sRGB.  The data are
            % scaled so that the largest value in display space (0,1) is
            % the same ratio as the peak sensor data value to the maximum
            % sensor output.
            %
            % N.B. The display on the user's desk is not likely to be the
            % calibrated display that is modeled.
            [img,vci] = displayRender(img,vci,s);
        otherwise
            error('Unknown transform method %s\n',tMethod);
    end
   
    % The display image RGB is always between 0 and 1. 
    %
    % Normally, we set the maximum image value to match the ratio of the
    % maximum voltage to the voltage swing.
    % In some cases - say for an ideal sensor with extremely large voltage
    % swing that we use in theory, this forces the data to be very small.
    % In that case, you should scale the data to max function.
    %
    % range of the sensor data, with the assumption that 0 in the sensor
    % corresponds to 0 in the image processing data.
    %
    imgMax = max(img(:));
    
    % Changed sensor to sensor(1) to deal with sensor array case.
    img = (img/imgMax)*sensorGet(sensor(1),'response ratio');

    % Clip the img data and attach it to the vci
    img = ieClip(img,0,ipGet(vci,'max sensor'));
    vci = ipSet(vci,'result',img);
    
    % macbethSelect rect handles -- get rid of them
    vci = ipSet(vci,'mccRectHandles',[]);
end

return;

function vci = vciComputeBracketed(vci,sensor,combinationMethod)
% Compute for bracketed exposure case
%
% sensor = vcGetObject('sensor');
% vci = vcGetObject('vcimage');
%
if ieNotDefined('vci'), error('Virtual camera image required.'); end
if ieNotDefined('sensor'), error('Image sensor array requried.'); end
if ieNotDefined('combinationMethod')
    combinationMethod = ipGet(vci,'combinationMethod'); 
end

% Could send this parameter in.  It is the value we accept as below saturation
satPercentage = 0.95;
expTimes      = sensorGet(sensor,'expTimes');

% Get the data, either as volts or digital values.
% Indicate which on return
img       = ipGet(vci,'input');
sensorMax = ipGet(vci,'maximum sensor value');
satMax    = satPercentage*sensorMax;

% Set values > saturatation value to -1 in the img array
img(img > satMax) = 0;

%% Estimate a sensor value accounting for all of the exposures
%
switch combinationMethod
    case 'longest'
        % Choose the max at each point
        [img,loc] = max(img,[],3);
        expByLoc  = expTimes(loc);
        img = img ./ expByLoc;               
    otherwise
        error('Unknown combination method: %s\n', combinationMethod)
end

% The largest value we can ever get
vci = ipSet(vci,'sensorMax',sensorMax/min(expTimes));
vci = ipSet(vci,'input',img);

return;

function vci = vciComputeCFA(vci,sensor)
% Compute for CFA exposure case
%
% In this case the img is N different CFA arrays, with each N corresponding
% to an exposure for one of the color filters.
% Our goal is to normalize the four CFA arrays by their exposure times, and
% then to pick out the relevant color terms from each of the exposures and
% merge them back into a single CFA.
%

if ieNotDefined('vci'), error('Virtual camera image required.'); end
if ieNotDefined('sensor'), error('Image sensor array requried.'); end

% sensor = vcGetObject('sensor');
% vci = vcGetObject('vcimage');
%

% Read the exposure times - same as number of filters
expTimes = sensorGet(sensor,'expTimes');
nExps    = length(expTimes(:));
% Get the data, either as volts or digital values.
% Indicate which on return
img       = ipGet(vci,'input');
sensorMax = ipGet(vci,'maximum sensor value');

% We are not sure how to handle the fact that channels can be saturated but
% with different exposure durations.  In that case, when we normalize by
% the exposure time, they may end up at different levels - even though in
% fact they were both saturated pxiels.
mx     = sensorMax/min(expTimes(:));

%% Normalize the values as if they had been captured at the same duration
%
cfaSize = size(sensorGet(sensor,'pattern'));
nRows   = sensorGet(sensor,'row');
nCols   = sensorGet(sensor,'col');

% We haven't dealt properly with saturation.  Must fix - MP

% Make one array that will hold CFA data after getting the color intensity
% values from appropriate exposure planes
newImg  = zeros(nRows,nCols);


for kk = 1:nExps
    
    % Note: The value for the kkth position in the CFA block (in
    % vectorized form) comes from the kkth exposure plane
    tmp = zeros(nRows,nCols);
    
    [ii,jj] = ind2sub(cfaSize,kk);   
    rows = ii:cfaSize(1):nRows;
    cols = jj:cfaSize(2):nCols;
    
    tmp(rows,cols) = img(rows,cols,kk);
    
    % Check to see if any of these pixels are saturated
    satInd = (tmp > 0.99*sensorMax);

    % Normalize intensity values to get intensity/s
    tmp = tmp/expTimes(ii,jj);
    
    % Set saturated pixels to the maximum possible pixel value
    tmp(satInd) = mx;

    % Now replace the rows and columns corresponding to the current color
    % into identical positions in newImg
    newImg(rows,cols) = tmp(rows,cols);
    
end

% Update sensorMax with the largest value we can ever get
vci = ipSet(vci,'sensorMax',mx);
vci = ipSet(vci,'input',newImg);

return;

