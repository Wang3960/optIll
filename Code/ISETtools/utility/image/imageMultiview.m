function selectedObjs = imageMultiview(objType, selectedObjs, singlewindow)
% Display multiple images of selected GUI objects
%
%  selectedObjs = imageMultiview(objType, selectedObjs, singlewindow)
%
% This routine lets the user compare the images side by side, rather than
% flipping through them in the GUI window.
%
% objType:       Which window (scene, oi, sensor, or vcimage)
% selectedObjs:  List of the selected object numbers, e.g., [1 3 5]
% singlewindow:  Put the images in subplots of a single figure (true) or in
%                different figures (default = false);
%
% See also: imageMontage
%
% Example:
%  objType = 'scene';
%  imageMultiview(objType);
%
%  selectedObjs = [1 6];
%  imageMultiview(objType,whichObj);
%
%  objType = 'vcimage';
%  selectedObjs = [2 3 5];
%  imageMultiview(objType,whichObj, true);
%
% Copyright Imageval Consultants, LLC, 2013

if ieNotDefined('objType'), error('Object type required.'); end
if ieNotDefined('singlewindow'), singlewindow = false; end

% Allows some aliases to be used
objType = vcEquivalentObjtype(objType);

% Get the objects
[objList, nObj] = vcGetObjects(objType);
if  isempty(objList)
    fprintf('No objects of type %s\n',objType);
    return;
end

% Show a subset or all
if ieNotDefined('selectedObjs')
    lst = cell(1,nObj);
    for ii=1:nObj, lst{ii} = objList{ii}.name; end
    selectedObjs = listdlg('ListString',lst);
end

% Adjust for the selected objects only
nObj = length(selectedObjs);

% Set up the subplots or multiple window conditions
if singlewindow
    if nObj > 3
        rWin = ceil(sqrt(nObj));
        cWin = ceil(nObj/rWin); fType = 'upper left';
    else
        rWin = nObj; cWin = 1; fType = 'tall';
    end
else   rWin = []; fType = 'upper left';
end
subCount = 1; % Which subplot are we in

%% This is the display loop
for ii=selectedObjs
    if (~singlewindow || subCount == 1), vcNewGraphWin([],fType); end
    if singlewindow
        subplot(rWin,cWin,subCount); subCount = subCount+1; 
    end
    switch objType
        case 'SCENE'
            gam = ieSessionGet('scene gamma');      % gamma in the window!
            displayFlag = ieSessionGet('scene display flag'); % RGB, HDR, Gray
            sceneShowImage(objList{ii},displayFlag,gam);
            t = sprintf('Scene %d - %s',ii,sceneGet(objList{ii},'name'));
            
        case 'OPTICALIMAGE'
            gam = ieSessionGet('oi gamma');      % gamma in the window!
            displayFlag = ieSessionGet('oi display flag'); % RGB, HDR, Gray
            oiShowImage(objList{ii},displayFlag,gam);
            t =sprintf('OI %d - %s',ii,oiGet(objList{ii},'name'));
            
        case 'ISA'
            gam = ieSessionGet('sensor gamma');      % gamma in the window!
            scaleMax = true; showFig = false;
            img = sensorShowImage(objList{ii},gam,scaleMax,showFig);
            imagesc(img); axis off;
            t = sprintf('Sensor %d - %s',ii,sensorGet(objList{ii},'name'));
            
        case 'VCIMAGE'
            gam = ieSessionGet('ip gamma');      % gamma in the window!
            trueSizeFlag = []; showFig = false;
            img = imageShowImage(objList{ii},gam,trueSizeFlag,showFig);
            imagesc(img); axis off; axis image
            t = sprintf('VCI %d - %s',ii,ipGet(objList{ii},'name'));
            
        otherwise
            error('Unsupported object type %s\n', objType);
    end
    
    % Label the image or window
    if singlewindow,      title(t)
    else                  set(gcf,'name',t);
    end
    
end

end


