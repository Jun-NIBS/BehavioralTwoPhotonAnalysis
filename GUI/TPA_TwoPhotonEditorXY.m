function [Par] = TPA_TwoPhotonEditorXY(Par)
%
% TPA_TwoPhotonEditorXY - Graphical interface to select rectangle or/and ellipse
%             regions of interest over a picture. It's also possible
%             to move, delete, change type and color or resize the
%             selections.
%
% Depend:     Global image data from TwoPhoton experiment. 
%
% Input:      Par       - structure of differnt constants 
%             SData.imTwoPhoton - (global) any 4D image array such as image=imread('demo.jpg') - 
%             SData.strROI   - (global) previous selection produced by this same application
%
% Output:     ROI produced (see Input ROI for format)
%
%
% Credits to: Jean Bilheux - November 2012 - bilheuxjm@ornl.gov
%

%-----------------------------
% Ver	Date	 Who	Descr
%-----------------------------
% 19.17 03.01.15 UD     adding move of all ROIs
% 19.16 31.12.14 UD     speedup by non computing image transforms again
% 19.15 18.12.14 UD     allow smaller ROIs and STD image for Adam
% 19.07 03.10.14 UD     improving ROI separation from different stacks
% 19.03 10.08.14 UD     Adding ROI selection by name
% 18.09 06.07.14 UD     Janelia back. Adding ROI tag of cell part
% 18.06 15.05.14 UD     Move all ROI together
% 17.08 05.04.14 UD     delete of ROI is not correct - changing to array delete. Majot bug - index is not correct at export.
% 17.06 27.03.14 UD     support load of ROIs without any structure only xy coordinates
% 17.04 22.03.14 UD     strManager Counters - at least as number of ROIs
% 16.18 25.02.14 UD     ROI z position
% 16.16 24.02.14 UD     Do not delete info during import
% 16.10 21.02.14 UD     comm open for sync pos
% 16.09 21.02.14 UD     Get 4 windows sync back on move
% 16.07 20.02.14 UD     Rename and changing ROI structure to support multiview
% 16.05 18.02.14 UD     Removing mouse browser.
% 16.04 18.02.14 UD     Sync other windows support
% 16.03 16.02.14 UD     Image Data is global
% 15.03 06.02.14 UD     Adding movie player
% 15.02 26.01.14 UD     ROI selection according to image button. Help with overlayed ROIs
% 15.01 08.01.14 UD     Adding features
% 15.00 07.01.14 UD     Merging with UserEditRoi
% 14.03 27.12.13 UD     File menu and Control buttons
% 14.02 26.12.13 UD     Changing ROI
% 13.04 25.12.13 UD     Browsing added
% 13.03 19.12.13 UD     Created
%-----------------------------

% connect to the global Data
global SData;

% connect to other windows and main gui for sync
global SGui;

% making it global only for TPA_ManageLastRoi
%global Par;

% % Debug
% if nargin < 1
%     %demoFile = 'cameraman.tif';
%     load('mri.mat','D');
%     SData.imTwoPhoton = D;
%     Par.PlayerMovieTime   = 10;
% end
% if nargin < 2,
%     ListROI             = {};
% end

% structure for GUI management (NUST BE REVISITED)
GUI_STATES          = Par.GUI_STATES;
guiState            = GUI_STATES.INIT;  % state of the gui
BUTTON_TYPES        = Par.BUTTON_TYPES;
buttonState         = BUTTON_TYPES.NONE;
ROI_TYPES           = Par.ROI_TYPES;
IMAGE_TYPES         = Par.IMAGE_TYPES;
EVENT_TYPES         = Par.EVENT_TYPES;
ROI_AVERAGE_TYPES   = Par.ROI_AVERAGE_TYPES;
ROI_CELLPART_TYPES  = Par.ROI_CELLPART_TYPES;


% structure with GUI handles
handStr             = [];

% active ROI
roiLast                = [];  % ROI under selection/editing

% contains all the rois - populated by roiLast
%roiStr                  = {};

%status of the left click
leftClick           = false;
rightClick          = false;

% image display
imageShowState      = IMAGE_TYPES.RAW;   % controls how image is displayed
imagePrevState      = IMAGE_TYPES.MAX;   % controls how image is displayed - previous
guiIsBusy           = false;             % prevent from multple updates during refresh


%are we moving the mouse with left click on ?
%motionClickWithLeftClick = false;

%used in selection of boxes
point1              = [-1 -1];
point2              = [-1 -1];

%reference position of rectangle to used when moving selection
pointRef            = [-1 -1];
%used when moving the selection
rectangleInitialPosition  = [-1 -1 -1 -1]; %rectangle to move
% used for freehand drawing and rectanglemovements
shapeInitialDrawing      = [0 0]; % coordinates of the shape

%used when moving selection
activeRectangleIndex = -1;
%previousActiveRectangleIndex = -1;

%['top','bottom','right','left','topl','topr','botl','botr','hand'
pointer             = 'crosshair'; %cursor shape

% parameter that controls sensitivity of the pointer to ROI borders        
szEdge              = 2; %pixels units
roiIsBeingEdited    = false;   % if you select any ROI all the info will be updated.
hideAllNames        = false;   % hide names of all ROIs

% create context menu
cntxMenu            = [];

% contain all the data
%D                   = [];
activeXaxisIndex        = 1;
activeYaxisIndex        = 1;
activeZstackIndex       = 1;
activeTimeIndex         = 1;
%activeIndexFixed    = true(4,1); % indicxates which index has not been changed
previousXYZTIndex       = [activeXaxisIndex activeYaxisIndex activeZstackIndex activeTimeIndex];

%-----------------------------------------------------
% init image

% what kind of data is there
[nR,nC,nZ,nT]           = size(SData.imTwoPhoton);
imageIn                 = squeeze(SData.imTwoPhoton(:,:,activeZstackIndex,activeTimeIndex)); %imread(demoFile);
imageInMean             = []; % used to remember calculations of STD
imageInStd              = [];

%-----------------------------------------------------
% init tool for ROI stratching and alignment
roiAlignStr             = []; %struct('fixedPoints',[],'movingPoints',[],'hFixed',[],'hMove',[],'closeInd',0);

%-----------------------------------------------------
% Window Sync Related
fCreateGUI();

% sync mechanism :  attach to update function in the main gui
fSyncAll                = getappdata(SGui.hMain, 'fSyncAll'); % called by main
setappdata(handStr.roiFig, 'fSyncRecv', @fSyncRecv);  % received from
% add this figure to list
srcId               = length(SGui.hChildList)+1; % used in communication
SGui.hChildList(srcId) = handStr.roiFig;
guiType             = Par.GUI_TYPES.TWO_PHOTON_XY; % self Id

% Init comm : must be global to spend multiple calls
SGui.usrInfo(srcId).posManager   = TPA_PositionManager(Par, guiType, srcId);
SGui.usrInfo(srcId).roiManager   = TPA_RoiMsgManager(Par, guiType, srcId);

%-----------------------------------------------------
% Init all
fCreateRoiContextMenu();
fRefreshImage();            % show the image
fImportROI();               % check that ROI structure is OK
fManageRoiArray('createView');
fRefreshImage();        % second time to show ROI on image


% = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
% Main Window

    function fCreateGUI()
        
        ScreenSize  = get(0,'ScreenSize');
        figWidth    = 800;
        figHeight   = 800;
        figX = (ScreenSize(3)-figWidth)/2;
        figY = (ScreenSize(4)-figHeight)/2;
        
                    
        roiFig = figure(...
            'numbertitle', 'off',...
            'WindowStyle','normal',...
            'name','4D : TwoPhoton Image Editor', ...
            'units', 'pixels',...
            'position',[figX, figY, figWidth, figHeight],... ceil(get(0,'screensize') .*[1 1 0.75 0.855] ),...
            'visible','off',...
            'menubar', 'none',...
            'toolbar','none',...
            'color',[0 0 0],...            
            'Interruptible','off',...   % How does it affect?            
            'Tag','AnalysisROI',...
            'WindowKeyPressFcn',        {@hFigure_KeyPressFcn}, ...
            'WindowButtonDownFcn',      {@hFigure_DownFcn}, ...
            'WindowButtonUpFcn',        {@hFigure_UpFcn}, ...
            'WindowButtonMotionFcn',    {@hFigure_MotionFcn}, ...
            'CloseRequestFcn',          {@fCloseRequestFcn});
        
        
        
        % UITOOLBAR
        % prepare icons
        s                       = load('TPA_ToolbarIcons.mat');
        
        ht                       = uitoolbar(roiFig);
        icon                     = im2double(imread(fullfile(matlabroot,'/toolbox/matlab/icons','tool_zoom_in.png')));
        icon(icon==0)            = NaN;
        uitoggletool(ht,...
            'CData',               icon,...
            'ClickedCallback',     'zoom',... @zoomIn,...
            'tooltipstring',       'ZOOM In/Out',...
            'separator',           'on');
        icon                     = im2double(imread(fullfile(matlabroot,'/toolbox/matlab/icons','tool_zoom_out.png')));
        icon(icon==0)            = NaN;
        uipushtool(ht,...
            'CData',               icon,...
            'ClickedCallback',     'zoom off',...@zoomOut,...
            'tooltipstring',       'ZOOM Out/Off');
        
       uipushtool(ht,...
            'CData',               s.ico.ml_arrow_d,...
            'separator',           'on',...            
            'ClickedCallback',     {@clickedNavToolZ,-1},...@prev,...
            'tooltipstring',       'Move down in Z stack/Video Channel');
       uipushtool(ht,...
            'CData',               s.ico.ml_arrow_u,...
            'ClickedCallback',     {@clickedNavToolZ,1},...@next,...
            'tooltipstring',       'Move up in Z stack/Video Channel');
       uipushtool(ht,...
            'CData',               s.ico.ml_arrow_l,...
            'ClickedCallback',     {@clickedNavToolXY,-1},...@prev,...
            'tooltipstring',       'Prev image in X axis');
       uipushtool(ht,...
            'CData',               s.ico.ml_arrow_r,...
            'ClickedCallback',     {@clickedNavToolXY,1},...@next,...
            'tooltipstring',       'Next image in X axis');
        
        browseTool = uitoggletool(ht, 'CData', s.ico.ml_tool_hand, ...
            'State',                'on', ...
            'enable',               'on',...           
            'TooltipString',        'Browse image data in T and Z using mouse',...
            'clickedCallback',      {@clickedToolButton,BUTTON_TYPES.BROWSE},...
            'tag',                  'browse_data');
        
        playerTool = uitoggletool(ht, 'CData',s.ico.player_play, ...
            'TooltipString',        'Play a movie at constant speed', ...
            'State',                'off', ...
            'clickedCallback',      {@clickedToolButton,BUTTON_TYPES.PLAYER},...            
            'tag',                  'player');
        
        
        icon                     = im2double(imread(fullfile(matlabroot,'/toolbox/images/icons','tool_contrast.png')));
        icon(icon==0)            = NaN;
        uipushtool(ht,...
            'CData',               icon,...
            'separator',           'on',...
            'ClickedCallback',     'imcontrast(gcf)',...
            'tooltipstring',       'Image contrast adjustment');
        

        %icon                    = im2double(imread('tool_rectangle.gif'));   icon(icon==0)            = NaN;
        rectangleTool           = uitoggletool(ht, 'CData',s.ico.rectangle, ...
            'TooltipString',    'Select a rectangular ROI', ...
            'separator',        'on',...
            'State',            'off', ...
            'clickedCallback', {@clickedToolButton,BUTTON_TYPES.RECT},...            
            'tag',              'rectangle_roi');
        
        %icon                     = im2double(imread('tool_shape_ellipse.png'));   icon(icon==0)            = NaN;
        ellipseTool             = uitoggletool(ht, 'CData',s.ico.ellipse, ...
            'TooltipString',    'Select an elliptical ROI', ...
            'clickedCallback', {@clickedToolButton,BUTTON_TYPES.ELLIPSE},...            
            'tag',              'ellipse_roi');
        
%             'tooltipstring',       'Setup Selected ROI Properties and Parameters ');
        
        freehandTool            = uitoggletool(ht, 'CData', s.ico.freehand, ...
            'State',            'off', ...
            'Enable',           'on',...
            'TooltipString',    'Select a freehand ROI',...
            'clickedCallback', {@clickedToolButton,BUTTON_TYPES.FREEHAND},...            
            'tag',              'freehand_roi');

        
        moveAllTool            = uitoggletool(ht, 'CData', s.ico.ml_star, ...
            'State',            'off', ...
            'Enable',           'on',...
            'TooltipString',    'Adjust all ROI regions together using reference points',...
            'clickedCallback', {@clickedToolButton,BUTTON_TYPES.MOVEALL},...            
            'tag',              'moveall_roi');
        
       hideAllTool            = uitoggletool(ht, 'CData', s.ico.win_bookmark, ...
            'State',            'off', ...
            'Enable',           'on',...
            'TooltipString',    'Hide names of all ROIs together',...
            'clickedCallback', {@clickedToolButton,BUTTON_TYPES.HIDEALL},...            
            'tag',              'hideall_roi');

        uitoggletool(ht,...
            'CData',               s.ico.win_copy,...
            'oncallback',          'warndlg(''Is yet to come'')',...@copyROIs,...
            'tooltipstring',       'Copy ROI(s): CTRL-1');
       
        uitoggletool(ht,...
            'CData',               s.ico.win_paste,...
            'oncallback',          'warndlg(''Is yet to come'')',...@pasteROIs,...
            'tooltipstring',       'Paste ROI(s): CTRL-2');
  
        uitoggletool(ht,...
            'CData',               s.ico.ml_del,...
            'oncallback',          'warndlg(''Is yet to come'')',...@deleteROIs,...
            'tooltipstring',       'Delete ALL ROI(s): CTRL-3');
        
        uitoggletool(ht,...
            'CData',               s.ico.xp_save,...
            'oncallback',          {@fExportROI},... %@saveSession,..
            'enable',              'off',...
            'tooltipstring',       'Save/Export Session: CTRL-s',...
            'separator',           'on');
        
        helpSwitchTool              = uipushtool(ht, 'CData', s.ico.win_help, ...
            'separator',            'on',...
            'TooltipString',        'A little help about the buttons',...
            'clickedCallback',      {@clickedHelpTool},...            
            'tag',                  'help');
        exitButton                  = uipushtool(ht, 'CData', s.ico.xp_exit, ...
            'separator',            'on',...
            'clickedCallback',      {@fCloseRequestFcn},...
            'TooltipString',        'Save, Close all and Exit',...
            'tag',                  'exit');
        

        % UIMENUS
        parentFigure = ancestor(roiFig,'figure');

        % FILE Menu
        f = uimenu(parentFigure,'Label','File...');
        uimenu(f,...
            'Label','Load Image...',...
            'callback','warndlg(''Is yet to come'')'); %,...@loadImage
        uimenu(f,...
            'Label','Save/Export Image',...
            'callback','warndlg(''Is yet to come'')');%,...@saveSession
        uimenu(f,...
            'Label','Close GUI',...
            'callback',@fCloseRequestFcn);

        % Image Menu
        menuImage(1) = uimenu(parentFigure,...
            'Label','Image ...');
        menuImage(2) = uimenu(menuImage(1),...
            'Label','Raw Data',...
            'checked','on',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.RAW});
        menuImage(3) = uimenu(menuImage(1),...
            'Label','Mean Projection',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.MEAN});
        menuImage(4) = uimenu(menuImage(1),...
            'Label','Max Projection',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.MAX});
        menuImage(5) = uimenu(menuImage(1),...
            'Label','Mean Time Difference',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.GRADT});
        menuImage(6) = uimenu(menuImage(1),...
            'Label','Mean Spatial Difference',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.GRADXY});
        menuImage(7) = uimenu(menuImage(1),...
            'Label','STD Projection',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.STD});
        menuImage(8) = uimenu(menuImage(1),...
            'Label','DFF Max Projection',...
            'checked','off',...
            'callback',{@fUpdateImageShow,IMAGE_TYPES.DFF});
        

        % ROIs Menu
        f = uimenu(parentFigure,...
            'Label','ROI...');
        uimenu(f,...
            'Label','Select ROI',...
            'callback',@fSelectRoiByName,...@defineROI,...
            'accelerator','r');
        uimenu(f,...
            'Label','Copy ROI(s)',...
            'callback','warndlg(''Is yet to come'')',...@copyROIs,...
            'accelerator','1');%c is reserved
        uimenu(f,...
            'Label','Paste ROI(s)',...
            'callback','warndlg(''Is yet to come'')',...@pasteROIs,...
            'accelerator','2');%v is reserved
        uimenu(f,...
            'Label','Delete ROI',...
            'callback',@fRemoveMarkedRoi,...@deleteROIs,...
            'accelerator','3');
        uimenu(f,...
            'Label','Set Color',...
            'callback',@fSelectColorForRoi,...{@advanceImage,+1},...
            'accelerator','n');
        uimenu(f,...
            'Label','Rename',...
            'callback',@fRenameRoi,...{@advanceImage,-1},...
            'accelerator','p');
        uimenu(f,...
            'Label','Average Type Select',...
            'callback',@fAverageTypeRoi,...
            'accelerator','a');
        uimenu(f,...
            'Label','Toggle Zoom',...
            'callback','zoom',...
            'accelerator','z');
        uimenu(f,...
            'Label','Save/Export Session',...
            'callback','warndlg(''Is yet to come'')',...@saveSession,...
            'accelerator','s');
        
          %create an axes for image and for roi
        imgAxes = axes();
        set(imgAxes, ...
            'tickdir','out', ...
            'drawmode','fast',...
            'position',[0.0 0.03 1 1]);
          
        imgShow                 = imagesc(imageIn,'parent',imgAxes);  colormap('gray'); hold on;
        imgNav                  = plot([10 10],[1 nR],'color','c','LineStyle',':');     hold off;        
        axis off;
        
        timeSlideTool           = uicontrol('style','slider','units','norm','back','k', ...
                                'pos',[0 0 1 .03],'min',1,'max',nT,'val',activeTimeIndex, ...
                                'sliderstep',[1/nT,0.03],'callback',@clickedSliderToolT,...
                                'TooltipString','Always browsing in Time');
   
        imgText                  = uicontrol('style','text','string','User Info','backg','k','foreg','y',...
                                    'units','norm','pos',[0 0.96 0.4 0.04],'FontUnits','pix','HorizontalAlignment','left');
        
        
        handStr.roiFig          = roiFig;
        handStr.imgAxes         = imgAxes;
        handStr.imgShow         = imgShow;
        handStr.imgNav          = imgNav;        
        handStr.imgText         = imgText;
        handStr.rectangleTool   = rectangleTool;
        handStr.ellipseTool     = ellipseTool;
        handStr.freehandTool    = freehandTool;
        handStr.moveAllTool     = moveAllTool;
        handStr.hideAllTool     = hideAllTool;
        handStr.browseTool      = browseTool;
        handStr.playerTool      = playerTool;
        handStr.helpSwitchTool  = helpSwitchTool;
        handStr.timeSlideTool   = timeSlideTool;
        handStr.menuImage       = menuImage;
        handStr.ico             = s.ico;
        
        drawnow
        
        %uiwait(roiFig);
        
    end

%-----------------------------------------------------
% Last ROI Management

   function fManageLastRoi(Cmnd,Data)
        if nargin < 2, Data = 0; end;
        
        switch Cmnd,
            
            case 'init',
                
                if strcmp(get(handStr.rectangleTool, 'State'),'on')
                        %fManageLastRoi('initRect',0)
                        roiType = ROI_TYPES.RECT;
                else
                    if strcmp(get(handStr.ellipseTool, 'State'),'on')
                        roiType = ROI_TYPES.ELLIPSE;
                        %fManageLastRoi('initEllipse',0)
                    else % freehand
                        roiType = ROI_TYPES.FREEHAND;
                        %fManageLastRoi('initFreehand',0)
                    end
                end;
                
                %fManageRoiArray('add',0); % add to the list    
                roiLast.Type     = roiType;
                fManageLastRoi('initFull',0);
                
                % compatability
             case 'initRect',
                % init new roi handle                
                roiLast.Type        = ROI_TYPES.RECT;
                 fManageLastRoi('initFull',Data);
               
           case 'initEllipse',
                % init new roi handle
                roiLast.Type    = ROI_TYPES.ELLIPSE;
                fManageLastRoi('initFull',Data);
                
          case 'initFreehand',
                % init new roi handle
                roiLast.Type    = ROI_TYPES.FREEHAND;
                fManageLastRoi('initFull',Data);
                
             
            case 'initFull',                
                
                % Data contains 
                
                roiLast.Active   = true;   % designates if this pointer structure is in use
                roiLast.Color    = rand(1,3);   % generate colors
                roiLast.NameShow = false;       % manage show name
                roiLast.zInd     = activeZstackIndex;           % location in Z stack
                roiLast.tInd     = 1;           % location in T stack
                
                pos                 = [0 0 0.1 0.1];
                switch roiLast.Type,
                        case ROI_TYPES.RECT,
                            roiName         = 'Rect';
                            avType          = ROI_AVERAGE_TYPES.MEAN;
                            xy              = repmat(pos(1:2),5,1) + [0 0;pos(3) 0;pos(3) pos(4); 0 pos(4);0 0];
                            if numel(Data) > 4, xy = Data; end;
                            pos              = [min(xy) max(xy) - min(xy)];
                            
                        case ROI_TYPES.ELLIPSE,
                            roiName         = 'Ellipse';
                            avType          = ROI_AVERAGE_TYPES.MEAN;
                            xy               = repmat(pos(1:2),5,1) + [0 0;pos(3) 0;pos(3) pos(4); 0 pos(4);0 0];
                            if numel(Data) > 4, xy = Data; end;
                            pos              = [min(xy) max(xy) - min(xy)];
                            
                        case ROI_TYPES.FREEHAND,
                            roiName         = 'Freehand';
                            avType          = ROI_AVERAGE_TYPES.LINE_ORTHOG;
                            if numel(Data) > 4, 
                                xy           = Data; 
                                pos          = [min(xy) max(xy) - min(xy)];
                            else
                                xy           = point1(1,1:2);%hFree.getPosition;
                                pos          = pos + [xy 0 0];
                            end;

                        otherwise
                            error('Bad roiType')
                 end
                roiLast.Position = pos;   
                roiLast.xyInd    = xy;          % shape in xy plane
                roiLast.Name     = roiName;
                roiLast.AverType = avType;
                roiLast.CellPart = ROI_CELLPART_TYPES.ROI;
                roiLast.CountId  = 1; % counter Id
                
                fManageLastRoi('initShapesXY',0);
                
                 
             case 'initShapesXY',
                % initalizes all lines and figures for view

                view.xy          = roiLast.xyInd;
                view.pos         = roiLast.Position;
                view.posr        = PosToRect(view.pos);
                view.clr         = roiLast.Color;
                view.name        = roiLast.Name;

                curv                = [0 0];
                if roiLast.Type == ROI_TYPES.ELLIPSE, curv            = [1 1]; end;

                view.hShape  =  line('xdata',view.xy(:,1),'ydata',view.xy(:,2),...
                    'lineStyle','--',...
                    'lineWidth',1, ...
                    'Color',view.clr);
               view.hCornRect  =  line('xdata',view.posr(:,1),'ydata',view.posr(:,2),...
                   'lineStyle','--',...
                   'Marker','s',...
                   'MarkerSize',8,...
                   'Color',view.clr);
                view.hBoundBox = rectangle('position',view.pos,...% the order of rect and box is important
                    'lineStyle',':',...
                    'lineWidth',0.5, ...
                    'curvature',curv,... % added                            
                    'edgeColor',view.clr);
                view.hText      =  text(view.pos(1),view.pos(2),view.name,'color',view.clr,'interpreter','none');

                %  hide it
                set(view.hShape,   'visible','off')
                set(view.hBoundBox,'visible','off')
                set(view.hCornRect,'visible','off')
                set(view.hText,    'visible','off')

                % add context menu
                 set(view.hBoundBox,'uicontextmenu',cntxMenu)

                % output
                roiLast.XY = view;                 
                roiLast.YT = [];
                
            case 'addPoint',
                % add point to a freehand line
                newPoint                = Data;
                if isempty(newPoint), return; end;
                
                xData                   = [get(roiLast.XY.hShape,'xdata') newPoint(1)];
                yData                   = [get(roiLast.XY.hShape,'ydata') newPoint(2)];
                set(roiLast.XY.hShape,'xdata',xData,'ydata',yData ,'color','b');
                
                % no scaling after position set
                roiLast.Position        = [min(xData) min(yData) max(xData)-min(xData) max(yData)-min(yData)];
                
                %  show it
                set(roiLast.XY.hShape,   'visible','on')                                
                 
            case 'setPos',
                % redraw the last ROI object pos
                pos                     = Data;
                
                 switch roiLast.Type,
                     case ROI_TYPES.RECT,
                        xy          = repmat(pos(1:2),5,1) + [0 0;pos(3) 0;pos(3) pos(4); 0 pos(4);0 0];
                     case ROI_TYPES.ELLIPSE,
                        xyr         = pos(3:4)/2;        % radius
                        xyc         = pos(1:2)+ xyr;     % center
                        tt          = linspace(0,2*pi,30)';
                        xy          = [cos(tt)*xyr(1) + xyc(1), sin(tt)*xyr(2) + xyc(2)];
                     case ROI_TYPES.FREEHAND,
                        pos_old     = rectangleInitialPosition;
                        xy_old      = shapeInitialDrawing;
                        % rescale
                        xyc         = pos(1:2)      + pos(3:4)/2;     % center
                        xyc_old     = pos_old(1:2)  + pos_old(3:4)/2;     % center
                        x           = (xy_old(:,1) - xyc_old(1))*pos(3)/(eps+pos_old(3)) + xyc(1);
                        y           = (xy_old(:,2) - xyc_old(2))*pos(4)/(eps+pos_old(4)) + xyc(2); 
                        xy          = [x(:) y(:)];
                 end;
                roiLast.Position        = pos; %[x,y,w,h]
                posr                    = PosToRect(pos);

                
                % rect to xy
                set(roiLast.XY.hShape,     'xdata',xy(:,1),'ydata',xy(:,2),'visible','on');
                set(roiLast.XY.hBoundBox,  'position',roiLast.Position,'visible','on');
                set(roiLast.XY.hCornRect,  'xdata',posr(:,1),'ydata',posr(:,2),'visible','on');
                
%                 cornerRectangles        = getCornerRectangles(roiLast.Position);
%                 for j=1:8,
%                     set(roiLast.XY.hCornRect(j), 'position',cornerRectangles{j},'visible','on');
%                 end
                set(roiLast.XY.hText,'pos',roiLast.Position(1:2)+[5,5], 'visible','on')
                
            case 'setClr',
                % redraw the last ROI object pos
                clr                 = Data;
                roiLast.Color       = clr;   % remember
                set(roiLast.XY.hShape,     'Color',    clr);
                set(roiLast.XY.hBoundBox,  'edgeColor',clr);
                set(roiLast.XY.hCornRect,  'Color',    clr);
                set(roiLast.XY.hText,      'color',    clr)
               
            case 'setName',
                % redraw the last ROI object pos
                roiLast.Name        = Data;   % remember
                set(roiLast.XY.hText,  'string', roiLast.Name,   'visible','on')
                              
             case 'setAverType',
                % properties for the subsequent processing
                roiLast.AverType        = Data;   % remember               
                
             case 'setCellPartType',
                % properties for the subsequent processing
                roiLast.CellPart        = Data;   % remember               
                
            case 'setZInd',
                % stack position
                roiLast.zInd            = Data;
                
            case 'setTInd',
               roiLast.tInd             = Data;           % location in T stack
                                
            case 'clean',
                % delete graphics of the lastROI
                if activeRectangleIndex < 1, return; end;
                
                %remove the rectangle at the index given
                delete(roiLast.XY.hShape);
                delete(roiLast.XY.hBoundBox);
                delete(roiLast.XY.hCornRect);
                delete(roiLast.XY.hText);
               
                activeRectangleIndex = -1;
                
            case 'updateView',

                % redraw XY view according to info from YT view
                
                % check if YT is initialized
                if ~isfield(roiLast.YT,'hBoundBox'), return; end;
                
                % extract Y length from YT space
                posXY                = get(roiLast.XY.hBoundBox,'pos');
                posYT                = get(roiLast.YT.hBoundBox,'pos');
                
                % position is defined by 
                posXY([2 4])         = posYT([2 4]);
                
                % redefine the shape
                fManageLastRoi('setPos',posXY);                
                % update color
                fManageLastRoi('setClr',roiLast.Color);                
 
            case 'createView',

                % redraw XY view according to info from YT view
                
                % check if YT is initialized
                %if ~isfield(roiLast.YT,'hBoundBox'), return; end;
                if ~isfield(roiLast.YT,'hBoundBox'), return; end;
                
                % extract Y length from YT space
                posYT                = get(roiLast.YT.hBoundBox,'pos');
                
                % position is defined by 
                posXY([2 4])         = posYT([2 4]);
                posXY([1 3])         = [10 nC-20];    
                
               switch roiLast.Type,
                     case ROI_TYPES.ELLIPSE,
                        curv           = [1,1]; % curvature
                    otherwise
                        curv           = [0,0]; % curvature
                end;
                
                
                % init shapes
                pos                  = posXY;
                xy                   = repmat(pos(1:2),5,1) + [0 0;pos(3) 0;pos(3) pos(4); 0 pos(4);0 0];                
                clr                 = 'y';
                roiLast.XY.hShape  =  line('xdata',xy(:,1),'ydata',xy(:,2),...
                        'lineStyle','--',...
                        'lineWidth',1, ...
                        'Color',clr);
                roiLast.XY.hBoundBox = rectangle('position',pos,...
                        'lineStyle',':',...
                        'lineWidth',0.5, ...
                        'curvature',curv,...                       
                        'edgeColor',clr);
                cornerRectangles = getCornerRectangles(pos);
                for j=1:8,
                 roiLast.XY.hCornRect(j) = rectangle('position',cornerRectangles{j},...
                        'lineWidth',1, ...
                        'edgeColor',clr);
                end
                roiLast.XY.hText =  text(pos(1),pos(2),roiLast.Name,'color',roiLast.Color,'interpreter','none');  
                
                %  hide it
                set(roiLast.XY.hShape,   'visible','off')
                set(roiLast.XY.hBoundBox,'visible','off')
                set(roiLast.XY.hCornRect,'visible','off')
                set(roiLast.XY.hText,    'visible','off')
                
                % add context menu
                 set(roiLast.XY.hBoundBox,'uicontextmenu',cntxMenu)
                
                
                % redefine the shape
                fManageLastRoi('setPos',posXY);                
                % update color
                fManageLastRoi('setClr',roiLast.Color);                
                
            otherwise
                error('Unknown Cmnd : %s',Cmnd)

        end
   end

%-----------------------------------------------------
% Array ROI Management

   function fManageRoiArray(Cmnd,Data)
       % manage list of ROIs
        if nargin < 2, Data = 0; end;
        
        switch Cmnd,
                                           
            case 'copyFromList',
                % redraw the last ROI object pos
                activeIndx              = Data;
                roiNum                  = length(SData.strROI);
                if activeIndx < 1 || activeIndx > roiNum, error('Bad value for activeIndx'); end;
                
                roiLast                 = SData.strROI{activeIndx};
                SData.strROI{activeIndx}.Active = false;
                
                switch roiLast.Type,
                     case ROI_TYPES.ELLIPSE,
                        curv           = [1,1]; % curvature
                    otherwise
                        curv           = [0,0]; % curvature
                end;
                

                clr                     = SData.strROI{activeIndx}.Color;
                set(roiLast.XY.hShape,     'color',    clr,'visible','on');
                set(roiLast.XY.hBoundBox,  'edgeColor',clr,'visible','on', 'curvature', curv);
                set(roiLast.XY.hCornRect,  'Color',    clr,'visible','on');
                set(roiLast.XY.hText,      'color',    clr,'visible','on')
                
                % gui support
                rectangleInitialPosition    = SData.strROI{activeIndx}.Position;
                shapeInitialDrawing         = [get(roiLast.XY.hShape,'xdata')' get(roiLast.XY.hShape,'ydata')']; 
                
                % sync -  change color
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);                
                
            case 'copyToList',
                % redraw the last ROI object pos
                activeIndx              = Data;
                roiNum                  = length(SData.strROI);
                if activeIndx < 1 || activeIndx > roiNum, error('Bad value for activeIndx'); end;
                
                % update shape - important for circles and freehand
                %UD fManageLastRoi('setPos',roiLast.Position);
                
                % update name
                %fManageLastRoi('setName',sprintf('ROI:%2d Z:%d %s',activeIndx,roiLast.zInd,roiLast.AverType));                
                
                
                SData.strROI{activeIndx}      = roiLast;
                clr                           = 'y';
                set(SData.strROI{activeIndx}.XY.hShape,     'Color',     clr,'visible','on');
                set(SData.strROI{activeIndx}.XY.hBoundBox,  'edgeColor', clr,'visible','off', 'curvature', [0,0]);
                set(SData.strROI{activeIndx}.XY.hCornRect,  'Color',     clr,'visible','off');
                set(SData.strROI{activeIndx}.XY.hText,      'color',     clr,'visible','on')
                SData.strROI{activeIndx}.Active = true;
                
                % not in use any more
                %activeRectangleIndex   = 0;      
                % sync
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);                
                
            case 'delete',
                % delete from list
                activeIndx              = Data;
                roiNum                  = length(SData.strROI);
                if activeIndx < 1 || activeIndx > roiNum, error('Bad value for activeIndx'); end;
                
                %remove the rectangle at the index given
                delete(SData.strROI{activeIndx}.XY.hShape);
                delete(SData.strROI{activeIndx}.XY.hBoundBox);
                delete(SData.strROI{activeIndx}.XY.hCornRect);
                delete(SData.strROI{activeIndx}.XY.hText);
                if ~isempty(SData.strROI{activeIndx}.YT),
                delete(SData.strROI{activeIndx}.YT.hShape);
                delete(SData.strROI{activeIndx}.YT.hBoundBox);
                delete(SData.strROI{activeIndx}.YT.hCornRect);
                delete(SData.strROI{activeIndx}.YT.hText);
                end
                SData.strROI(activeIndx)      = [];
                
                % sync
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);                
                
            case 'add',

               %add the last rectangle ROI to the list of Rectangle ROIs
                
                activeIndx                  = length(SData.strROI) + 1;
                SData.strManager.roiCount   = SData.strManager.roiCount + 1;  % universal counter
                roiLast.CountId             = SData.strManager.roiCount;
                
                % update name
                roiName                     = sprintf('ROI:%2d Z:%d',roiLast.CountId,roiLast.zInd);
                fManageLastRoi('setName',roiName);
                
                
                SData.strROI{activeIndx}        = roiLast;
                clr                             = 'r';
                set(SData.strROI{activeIndx}.XY.hShape,     'Color',     clr,'visible','on');
                set(SData.strROI{activeIndx}.XY.hBoundBox,  'edgeColor', clr,'visible','on');
                set(SData.strROI{activeIndx}.XY.hCornRect,  'Color',     clr,'visible','on');
                set(SData.strROI{activeIndx}.XY.hText,      'color',     clr,'visible','on');
                
                        
                
                % when added - still selected
                activeRectangleIndex     = activeIndx;
                rectangleInitialPosition = roiLast.Position; % no scaling
                shapeInitialDrawing      = [get(roiLast.XY.hShape,'xdata')' get(roiLast.XY.hShape,'ydata')']; 
                
                % update shape - important for circles and freehand
                fManageLastRoi('setPos',roiLast.Position);
                
                % sync
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);                
            
            case 'updateView',
               
               % check if any rectangle is under editing : return it back
               if activeRectangleIndex > 0,
                   fManageRoiArray('copyToList',activeRectangleIndex);
                   activeRectangleIndex   = 0; 
               end

                % update view if it has been updated by other window
                roiNum                  = length(SData.strROI);
                for activeIndx = 1:roiNum,
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyFromList',activeIndx);                    
                    
                    % update shape - important for circles and freehand
                    fManageLastRoi('updateView',activeIndx);
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyToList',activeIndx);                    
                    
                end
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);
                
            case 'createView',
               % designed to init the structure when opened second
               % check if any rectangle is under editing : return it back
               if activeRectangleIndex > 0,
                   fManageRoiArray('copyToList',activeRectangleIndex);
               end

                % update view if it has been updated by other window
                roiNum                  = length(SData.strROI);
                for activeIndx = 1:roiNum,
                    
                    % do it simple since shapes are not initialized
                   % fManageRoiArray('copyFromList',activeIndx);    
                    roiLast            = SData.strROI{activeIndx};                   
                    
                    % update shape - important for circles and freehand
                    fManageLastRoi('createView',activeIndx);
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyToList',activeIndx);                    
                    
                end
                %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI); 
                
            case 'updatePos',
                % update position of all rectangles at once
               if numel(Data) ~=2, error('Must have X and Y for update position'); end
                
               % check if any rectangle is under editing : return it back
               if activeRectangleIndex > 0,
                   fManageRoiArray('copyToList',activeRectangleIndex);
                   activeRectangleIndex   = 0; 
               end

                % update view if it has been updated by other window
                roiNum                  = length(SData.strROI);
                for activeIndx = 1:roiNum,
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyFromList',activeIndx);             
                    
                    % check boundaries
                    moveDir         = Data; % x,y
                    pos             = roiLast.Position;
                    if sum(pos([1 3])) + moveDir(1) > nC,   moveDir(1) = 0; end
                    if pos(1) + moveDir(1)          < 1,    moveDir(1) = 0; end
                    if sum(pos([2 4])) + moveDir(2) > nR,   moveDir(2) = 0; end
                    if pos(2) + moveDir(2)          < 1,    moveDir(2) = 0; end
                    
                    % update shape - important for circles and freehand
                    pos             = pos + [moveDir(1) moveDir(2) 0 0];
                    fManageLastRoi('setPos',pos);
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyToList',activeIndx);                    
                    
                end
                
            case 'updateTransform',
                % update position of all rectangles at once using transform martix
               %if numel(Data) ~= 9, error('Must be matrix 3x3'); end
               assert(isa(Data,'struct'),'Must be tform object');
               t_form       = Data;
                
               % check if any rectangle is under editing : return it back
               if activeRectangleIndex > 0,
                   fManageRoiArray('copyToList',activeRectangleIndex);
                   activeRectangleIndex   = 0; 
               end

                % update view if it has been updated by other window
                roiNum                  = length(SData.strROI);
                for activeIndx = 1:roiNum,
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyFromList',activeIndx); 
                    
                    % transform position to corners
                    pos             = roiLast.Position;
                    posLR           = [sum(pos([1 3])) sum(pos([2 4]))]; % precompute
                    XY              = [pos(1:2);pos(1) posLR(2); posLR;posLR(1) pos(2)];
                    xy              = tformfwd(t_form,XY);
                    
                    % transform back to position - keep rectangles straite
                    xyMin           = min(xy);
                    xyMax           = max(xy);
                    pos_new         = [xyMin xyMax - xyMin];

                    
                    % check boundaries
                    if sum(pos_new([1 3]))  > nC,   pos_new = pos; end
                    if pos_new(1)           < 1,    pos_new = pos; end
                    if sum(pos_new([2 4]))  > nR,   pos_new = pos; end
                    if pos_new(2)           < 1,    pos_new = pos; end
                    
                    % update shape - important for circles and freehand
                    fManageLastRoi('setPos',pos_new);
                    
                    % unknown effect -  it will flicker
                    fManageRoiArray('copyToList',activeIndx);                    
                    
                end
                
                
            otherwise
                error('Unknown Cmnd : %s',Cmnd)

        end
   end

%-----------------------------------------------------
% ROI Commands

    function fCreateRoiContextMenu()
    cntxMenu = uicontextmenu;
    uimenu(cntxMenu,'Label','Remove ROI',    'Callback',         @fRemoveMarkedRoi);
    uimenu(cntxMenu,'Label','Select Color',  'Callback',         @fSelectColorForRoi);
    uimenu(cntxMenu,'Label','Rename',        'Callback',         @fRenameRoi);
    uimenu(cntxMenu,'Label','Aver Type',     'Callback',         @fAverageTypeRoi);
    uimenu(cntxMenu,'Label','Cell Part Type','Callback',         @fCellPartTypeRoi);
    uimenu(cntxMenu,'Label','Show name',     'Callback',         @fShowNameRoi, 'checked', 'off');
    uimenu(cntxMenu,'Label','Snap to Data',  'Callback',         'warndlg(''TBD'')');
    end

    function fRemoveMarkedRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;

        fManageRoiArray('delete',activeRectangleIndex);
        activeRectangleIndex    = -1;
        guiState =  GUI_STATES.ROI_INIT; 
        set(handStr.roiFig, 'pointer','arrow');
        fRefreshImage();

    end

    function fSelectColorForRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;

        selectedColor = uisetcolor('Select a Color for the cell');
        if(selectedColor == 0),         return;     end
        fManageLastRoi('setClr',selectedColor);

    end

    function fRenameRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;

        prompt      = {'Enter ROI Name:'};
        dlg_title   = 'ROI parameters';
        num_lines   = 1;
        def         = {roiLast.Name};
        answer      = inputdlg(prompt,dlg_title,num_lines,def);
        if isempty(answer), return; end;
        fManageLastRoi('setName',answer{1});

    end

    function fAverageTypeRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;
                
        RoiAverageOptions = Par.Roi.AverageOptions; %{'PointAver','LineMaxima','LineOrthog'};
        [s,ok] = listdlg('PromptString','Select ROI Averaging Type:','ListString',RoiAverageOptions,'SelectionMode','single');
        if ~ok, return; end;
        fManageLastRoi('setAverType',getfield(Par.ROI_AVERAGE_TYPES,RoiAverageOptions{s}));

    end

    function fCellPartTypeRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;
                
        [s,ok] = listdlg('PromptString','Select ROI Averaging Type:','ListString', Par.Roi.CellPartOptions,'SelectionMode','single');
        if ~ok, return; end;
        fManageLastRoi('setCellPartType',getfield(Par.ROI_CELLPART_TYPES,Par.Roi.CellPartOptions{s}));
        
        % update name
        roiName                     = sprintf('%s:%2d Z:%d',Par.Roi.CellPartOptions{s},roiLast.CountId,roiLast.zInd);
        fManageLastRoi('setName',roiName);
        

    end

    function fShowNameRoi(src,eventdata)

        % activate menu only when active index is OK
        if activeRectangleIndex < 1, return; end;

        roiLast.NameShow  = strcmp(get(src,'Checked'),'on');

    end

    function fSelectRoiByName(src,eventdata)
        % Allows user to select ROI from list of names  

        % return any active back to place
        if activeRectangleIndex > 0,
            fManageRoiArray('copyToList',activeRectangleIndex);
        end

        % create name list
        roiNum      = length(SData.strROI);
        roiNames    = {};
        for m = 1:roiNum,
            roiNames{m}    = SData.strROI{m}.Name;
        end
        
        [s,ok]      = listdlg('PromptString','Select ROI by Name:','ListString', roiNames,'SelectionMode','single');
        if ~ok, return; end;
        
        activeRectangleIndex   = s; 
        % select this ROI from the list
        fManageRoiArray('copyFromList',activeRectangleIndex);            
        fManageLastRoi('updateView',activeRectangleIndex);
        fManageLastRoi('setClr','g');
        %fManageRoiArray('copyToList',activeRectangleIndex);
        %activeRectangleIndex = -1;
                
        guiState        = GUI_STATES.ROI_SELECTED;        
        fRefreshImage();
        

    end


%-----------------------------------------------------
% ROI Input & Output

    function fImportROI()
        %This function will parse the ROI from the main gui roi list
        %and check that everithing is OK
        
       
        % refresh the structure
        roiNum             = length(SData.strROI);
        badRoiId           = false(1,roiNum);
        %roiMaxId           = 0;  % reset global Id number
        for i=1:roiNum,
            
            % check the XY size only if less than 7x7 pix - kill
            thisRoiAreaOK                 = true;   
            thisRoiNeedsInit              = true;   
            
            % support roi types
            if isfield(SData.strROI{i},'Type'),
                thisRoiNeedsInit         = false;
            end;
            
            % support count id
            if ~isfield(SData.strROI{i},'CountId'),
                SData.strROI{i}.CountId  = i;
            end;
            
            
            currentXY                   = [1 1; 1 3;3 3;3 1; 1 1];
            if isfield(SData.strROI{i},'xyInd')
                currentXY               = SData.strROI{i}.xyInd;
            else
                thisRoiAreaOK             = false;
            end
            
            % check area
            rectArea                    = prod(max(currentXY) - min(currentXY));
            if rectArea < 10,
                thisRoiAreaOK             = false;
            end
            
            % check max Id            
            if thisRoiAreaOK , 
                
                if thisRoiNeedsInit,
                    roiLast.Type     = ROI_TYPES.ELLIPSE;
                    roiLast.CountId  = i;
                    fManageLastRoi('initFreehand',currentXY);
                    fManageLastRoi('setName',sprintf('ROI:%2d Z:%d',i,activeZstackIndex));
                else                
                    roiLast         = SData.strROI{i};   
                    fManageLastRoi('initShapesXY',0);
               end
                
                % add to the pool
                fManageRoiArray('copyToList',i)
                
            else            
                %fManageRoiArray('delete',i)
                badRoiId(i) = true;
                
           end

        end
        
        % protect if old data is used
        SData.strManager.roiCount   = max(SData.strManager.roiCount,roiNum);  % universal counter

        % clean bad ROIs
        for i = 1:roiNum,
            if ~badRoiId(i), continue; end;
            %fManageRoiArray('delete',i);
            SData.strROI{i} = [];
            DTP_ManageText([], sprintf('TwoPhoton : ROI %d is deleted',i), 'E' ,0)   ;
        end
        
        DTP_ManageText([], sprintf('TwoPhoton XY : %d ROIs are Imported',roiNum), 'I' ,0)   ;

        activeRectangleIndex = -1; % none is selected
    end

    function fExportROI()

        %This function will parse the ROI from the main gui roi list
        %and check that everithing is OK

        roiNum      = length(SData.strROI);
        %[Y,X]       = meshgrid(1:nR,1:nC);
        [X,Y]       = meshgrid(1:nR,1:nC);  % export
        %roiList = {};     
        %return
        for i=1:roiNum,
            
            % check for problems
            if isempty(SData.strROI{i}.XY.hShape),
                continue;
            end
            
            %pos                 = SData.strROI{i}.Position;
            xy                  = [get(SData.strROI{i}.XY.hShape,'xdata')' get(SData.strROI{i}.XY.hShape,'ydata')'];
            SData.strROI{i}.xyInd    = xy; %[pos(1:2); pos(1:2)+[0 pos(4)];pos(1:2)+pos(3:4);pos(1:2)+[pos(3) 0]];
            %SData.strROI{i}.Type;
            %SData.strROI{i}.Color;
            %roiList{i}.name     = sprintf('ROI:%2d Z:%d %s',i,SData.strROI{i}.zInd,SData.strROI{i}.AverType);
            %roiList{i}.averType = SData.strROI{i}.AverType;
            %roiList{i}.zInd     = SData.strROI{i}.zInd;
            % actual indexes
            maskIN                = inpolygon(X,Y,xy(:,1),xy(:,2));
            SData.strROI{i}.Ind  = find(maskIN);
            
            delete(SData.strROI{i}.XY.hShape);          SData.strROI{i}.XY.hShape = [];
            delete(SData.strROI{i}.XY.hBoundBox);       SData.strROI{i}.XY.hBoundBox = [];
            delete(SData.strROI{i}.XY.hCornRect);       SData.strROI{i}.XY.hCornRect = [];
            delete(SData.strROI{i}.XY.hText);           SData.strROI{i}.XY.hText = [];
            
            % do not touch old data
            if roiIsBeingEdited,
                % mean if any ois invalidated
                SData.strROI{i}.meanROI   = [];
                SData.strROI{i}.procROI   = [];
            end;
            
        end
        
%         % start save
%         if roiIsBeingEdited,
%                 buttonName = questdlg('Would you like to save ROI data', 'Warning');
%                 if strcmp(buttonName,'Yes'),  
%                 end
%         end

        Par.DMT                 = Par.DMT.SaveAnalysisData(Par.DMT.Trial,'strROI',SData.strROI);  
        DTP_ManageText([], sprintf('TwoPhoton XY : %d ROIs are saved',roiNum), 'I' ,0) ;
        
        
    end


%-----------------------------------------------------
% ROI Position

   function [yesItIs, index, isEdge, whichEdge_trbl] = isMouseOverRectangle()
        %this function will determine if the mouse is
        %currently over a previously selected Rectangle
        %
        %yesItIs: true or false
        %index; if yesItIs, returns the index of the rectangle selected
        %isEdge: true or false (are we over the rectangle, or just the
        % edge). Just the edge means that the rectangle will be resized
        % when over the center will mean replace it !
        %whichEdge: 'top', 'left', 'bottom' or 'right' or combination of
        % 'top-left'...etc
        
        yesItIs = false;
        index = -1;
        isEdge = false;
        whichEdge_trbl = [false false false false];
        
        point = get(handStr.imgAxes, 'CurrentPoint');
        
        sz = length(SData.strROI);
        for i=1:sz,
            
            % check if belongs to the z stack
            if SData.strROI{i}.zInd ~= activeZstackIndex, continue; end;
            
            % check if belongs to the button group
            %if SData.strROI{i}.Type ~= buttonState, continue; end;  
            switch buttonState,
                case BUTTON_TYPES.RECT,
                        if SData.strROI{i}.Type ~= ROI_TYPES.RECT,
                            continue;
                        end
                case BUTTON_TYPES.ELLIPSE
                        if SData.strROI{i}.Type ~= ROI_TYPES.ELLIPSE,
                            continue;
                        end
               case BUTTON_TYPES.FREEHAND
                        if SData.strROI{i}.Type ~= ROI_TYPES.FREEHAND,
                            continue;
                        end
               otherwise
                    % nothing is sellected
                    continue
            end                
            
            
            [isOverRectangle, isEdge, whichEdge_trbl] = isMouseOverEdge(point, SData.strROI{i}.Position);
            if isOverRectangle, % && SData.strROI{i}.Active, % Active helps when one of the rectangles is under editing
                % check if the selection tool fits SData.strROI{i}.Type
                yesItIs = true;
                index = i;
                break
            end
        end
        
    end

   function [result, isEdge, whichEdge_trbl] = isMouseOverEdge(point, rectangle)
        %check if the point(x,y) is over the edge of the
        %rectangle(x,y,w,h)
        
        
        result = false;
        isEdge = false;
        whichEdge_trbl = [false false false false]; %top right bottom left
        
        xMouse = point(1,1);
        yMouse = point(1,2);
        
        xminRect = rectangle(1);
        yminRect = rectangle(2);
        xmaxRect = rectangle(3)+xminRect;
        ymaxRect = rectangle(4)+yminRect;
        
        %is inside rectangle
        if (yMouse > yminRect-szEdge && ...
                yMouse < ymaxRect+szEdge && ...
                xMouse > xminRect-szEdge && ...
                xMouse < xmaxRect+szEdge)
            
            %is over left edge
            if (yMouse > yminRect-szEdge && ...
                    yMouse < ymaxRect+szEdge && ...
                    xMouse > xminRect-szEdge && ...
                    xMouse < xminRect+szEdge)
                
                isEdge = true;
                whichEdge_trbl(4) = true;
            end
            
            %is over bottom edge
            if (xMouse > xminRect-szEdge && ...
                    xMouse < xmaxRect+szEdge && ...
                    yMouse > ymaxRect-szEdge && ...
                    yMouse < ymaxRect+szEdge)
                
                isEdge = true;
                whichEdge_trbl(3) = true;
            end
            
            %is over right edge
            if (yMouse > yminRect-szEdge && ...
                    yMouse < ymaxRect+szEdge && ...
                    xMouse > xmaxRect-szEdge && ...
                    xMouse < xmaxRect+szEdge)
                
                isEdge = true;
                whichEdge_trbl(2) = true;
            end
            
            %is over top edge
            if (xMouse > xminRect-szEdge && ...
                    xMouse < xmaxRect+szEdge && ...
                    yMouse > yminRect-szEdge && ...
                    yMouse < yminRect+szEdge)
                
                isEdge = true;
                whichEdge_trbl(1) = true;
            end
            
            result = true;
            
        end
        
    end

   function cornerRectangles = getCornerRectangles(currentRectangle)
        %this function will create a [8x4] array of the corner
        %rectangles used to show the user that it can resize the ROI
        
        cornerRectangles = {};
        
        x = currentRectangle(1);
        y = currentRectangle(2);
        w = currentRectangle(3);
        h = currentRectangle(4);
        
        units=get(handStr.roiFig,'units');
        set(handStr.roiFig,'units','pixels');
        roiFigPosition      = get(handStr.roiFig,'position');
        roiFigWidth         = roiFigPosition(3);
        roiFigHeight        = roiFigPosition(4);
        set(handStr.roiFig,'units',units);
        
        wBox = roiFigWidth/200;
        hBox = roiFigHeight/200;
        
        %tl corner
        x1 = x - wBox/2;
        y1 = y - hBox/2;
        cornerRectangles{1} = [x1,y1,wBox,hBox];
        
        %t (middle of top edge) corner
        x2 = x + w/2 - wBox/2;
        y2 = y - wBox/2;
        cornerRectangles{2} = [x2,y2,wBox,hBox];
        
        %tr corner
        x3 = x + w - wBox/2;
        y3 = y - hBox/2;
        cornerRectangles{3} = [x3,y3,wBox,hBox];
        
        %r (middle of right edge) corner
        x4 = x + w - wBox/2;
        y4 = y + h/2 - hBox/2;
        cornerRectangles{4} = [x4,y4,wBox,hBox];
        
        %br corner
        x5 = x + w - wBox/2;
        y5 = y + h - hBox/2;
        cornerRectangles{5} = [x5,y5,wBox,hBox];
        
        %b (middle of bottom edge) corner
        x6 = x + w/2 - wBox/2;
        y6 = y + h - hBox/2;
        cornerRectangles{6} = [x6,y6,wBox,hBox];
        
        %bl corner
        x7 = x - wBox/2;
        y7 = y + h - hBox/2;
        cornerRectangles{7} = [x7,y7,wBox,hBox];
        
        %l (middle of left edge) corner
        x8 = x - wBox/2;
        y8 = y + h/2 - hBox/2;
        cornerRectangles{8} = [x8,y8,wBox,hBox];
        
    end

   function drawLiveRectangle()
        %draw a rectangle live with mouse moving
        
        %motionClickWithLeftClick = true;
        units = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        point2 = get(handStr.imgAxes, 'CurrentPoint');
        
        x = min(point1(1,1),point2(1,1));
        y = min(point1(1,2),point2(1,2));
        w = abs(point1(1,1)-point2(1,1));
        h = abs(point1(1,2)-point2(1,2));
        if w == 0
            w=1;
        end
        if h == 0
            h=1;
        end
        
        %save rectangle
        roiLast.Position = [x y w h];
        %fRefreshImage (); %plot the image
        fManageLastRoi('setPos',[x,y,w,h]);
        fManageLastRoi('setClr','blue');
        
        set(handStr.imgAxes,'units',units);
        
    end

   function drawLiveEllipse()
       % ellipse is generated by rectangle with curvature
       drawLiveRectangle();

    end

   function drawLiveFreehand()
        %draw a freehand shape with mouse moving
        
        %motionClickWithLeftClick = true;
        units = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        point2 = get(handStr.imgAxes, 'CurrentPoint');
        
        %fRefreshImage (); %plot the image
        fManageLastRoi('addPoint',point2(1,1:2));
        fManageLastRoi('setClr','blue');
        set(handStr.imgAxes,'units',units);
        
    end

    function moveLiveRectangle()
        %will move the rectangle selection
        
        %motionClickWithLeftClick = true;
        units = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        %point2 = get(handStr.imgAxes, 'CurrentPoint');
        
        
        %current mouse position
        curMousePosition = get(handStr.imgAxes,'CurrentPoint');
        
        %offset to apply
        deltaX = curMousePosition(1,1) - pointRef(1,1);
        deltaY = curMousePosition(1,2) - pointRef(1,2);
        
        roiLast.Position(1) = rectangleInitialPosition(1) + deltaX;
        roiLast.Position(2) = rectangleInitialPosition(2) + deltaY;
        
        
        %fRefreshImage();
        fManageLastRoi('setPos',roiLast.Position);
        fManageLastRoi('setClr','red');
        set(handStr.imgAxes,'units',units);

        
    end

    function moveEdgeRectangle()
        %will resize the rectangle by moving the left, right, top
        %or bottom edge
        
        %motionClickWithLeftClick = true;
        units = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        %point2 = get(handStr.imgAxes, 'CurrentPoint');
        
        %current mouse position
        curMousePosition = get(handStr.imgAxes,'CurrentPoint');
        
        %FIXME
        %make sure the program does not complain when width or height
        %becomes 0 or negative
        
        minWH = 1;  %rectangle is at least minWH pixels width and height
        
        switch pointer
            case 'left'
                
                %offset to apply
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                
                roiLast.Position(1) = rectangleInitialPosition(1) + deltaX;
                roiLast.Position(3) = rectangleInitialPosition(3) - deltaX;
                if roiLast.Position(3) <= minWH
                    roiLast.Position(3) = minWH;
                end
                
            case 'right'
                
                %offset to apply
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                
                roiLast.Position(3) = rectangleInitialPosition(3) + deltaX;
                
            case 'top'
                
                %offset to apply
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                
                roiLast.Position(2) = rectangleInitialPosition(2) + deltaY;
                roiLast.Position(4) = rectangleInitialPosition(4) - deltaY;
                
            case 'bottom'
                
                %offset to apply
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                
                roiLast.Position(4) = rectangleInitialPosition(4) + deltaY;
                
            case 'topl'
                
                %offset to apply
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                
                roiLast.Position(1) = rectangleInitialPosition(1) + deltaX;
                roiLast.Position(3) = rectangleInitialPosition(3) - deltaX;
                roiLast.Position(2) = rectangleInitialPosition(2) + deltaY;
                roiLast.Position(4) = rectangleInitialPosition(4) - deltaY;
                
            case 'topr'
                
                %offset to apply
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                
                roiLast.Position(3) = rectangleInitialPosition(3) + deltaX;
                roiLast.Position(2) = rectangleInitialPosition(2) + deltaY;
                roiLast.Position(4) = rectangleInitialPosition(4) - deltaY;
                
            case 'botl'
                
                %offset to apply
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                
                roiLast.Position(1) = rectangleInitialPosition(1) + deltaX;
                roiLast.Position(3) = rectangleInitialPosition(3) - deltaX;
                roiLast.Position(4) = rectangleInitialPosition(4) + deltaY;
                
            case 'botr'
                
                %offset to apply
                deltaY = curMousePosition(1,2) - pointRef(1,2);
                deltaX = curMousePosition(1,1) - pointRef(1,1);
                
                roiLast.Position(3) = rectangleInitialPosition(3) + deltaX;
                roiLast.Position(4) = rectangleInitialPosition(4) + deltaY;
                
        end
        
        %make sure we have the minimum width and height requirements
        if roiLast.Position(3) <= minWH
            roiLast.Position(3) = minWH;
        end
        if roiLast.Position(4) <= minWH
            roiLast.Position(4) = minWH;
        end
        % dbg
        %roiLast.Position
        
        %fRefreshImage();
        fManageLastRoi('setPos',roiLast.Position);
        fManageLastRoi('setClr','red');
        set(handStr.imgAxes,'units',units);
        
        
    end

    function showEdgeRectangle()
        % will change pointer to different shapes over selected rectangle
        
%         if activeRectangleIndex < 1, 
%             error('Sometyhing wrong with state management. Must be in state with rect selected')
%         end;
        
        
        [yesItIs, index, isEdge, whichEdge_trbl] = isMouseOverRectangle();
        if yesItIs && activeRectangleIndex == index %change color of this rectangle

            pointer = 'hand';
            if isEdge

                if isequal(whichEdge_trbl,[true false false false])
                    pointer = 'top';
                end
                if isequal(whichEdge_trbl,[false true false false])
                    pointer = 'right';
                end
                if isequal(whichEdge_trbl,[false false true false])
                    pointer = 'bottom';
                end
                if isequal(whichEdge_trbl,[false false false true])
                    pointer = 'left';
                end
                if isequal(whichEdge_trbl,[true true false false])
                    pointer = 'topr';
                end
                if isequal(whichEdge_trbl,[true false false true])
                    pointer = 'topl';
                end
                if isequal(whichEdge_trbl,[false true true false])
                    pointer = 'botr';
                end
                if isequal(whichEdge_trbl,[false false true true])
                    pointer = 'botl';
                end
            end
        else
            %activeRectangleIndex = -1;
            pointer = 'arrow';
        end
        set(handStr.roiFig, 'pointer',pointer);
        
    end


%-----------------------------------------------------
% Mouse Motion

    function hFigure_MotionFcn(~, ~)
        %This function is reached any time the mouse is moving over the figure
        
       switch guiState,
           case GUI_STATES.INIT, 
                % do nothing
           case GUI_STATES.BROWSE_ABSPOS,
               % go to the next state
                if leftClick %we need to draw something                  
                   % guiState = GUI_STATES.BROWSE_DIFFPOS;
                end
           case GUI_STATES.BROWSE_DIFFPOS,               
               % draw now roi
                if leftClick %we need to draw something               
                 % fUpdateBrowseData();
                end
           
           case GUI_STATES.ROI_INIT, 
                % do nothing
           case GUI_STATES.ROI_DRAW,
               % draw now roi
                if leftClick %we need to draw something 
                 switch roiLast.Type,
                     case ROI_TYPES.RECT,
                        drawLiveRectangle();
                     case ROI_TYPES.ELLIPSE,
                        drawLiveEllipse();
                     case ROI_TYPES.FREEHAND,
                        drawLiveFreehand();
                 end;
                end
                
                
           case GUI_STATES.ROI_MOVE,
                if leftClick %we need to draw something               
                   moveLiveRectangle();
                end
               
              
           case GUI_STATES.ROI_SELECTED,
               % change pointer over selected ROI
               showEdgeRectangle();
               
           case GUI_STATES.ROI_EDIT,
               % move ROI edges
                if leftClick %we need to draw something
                    moveEdgeRectangle();
                end
                
                
           case GUI_STATES.ROI_MOVEALL,
              % draging the point
              point = get(handStr.imgAxes, 'CurrentPoint');
              fManageReferencePoints('updateMove',point(1,1:2));
               
       end
    end

    function hFigure_DownFcn(~, ~)
        
        
        % get which button is clicked
        clickType   = get(handStr.roiFig,'Selectiontype');
        leftClick   = strcmp(clickType,'normal');
        rightClick  = strcmp(clickType,'alt');
        
        units       = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        point1      = get(handStr.imgAxes,'CurrentPoint');
        set(handStr.imgAxes,'units',units);
        pointRef    = point1;                        

        [yesItIs, index, isEdge, whichEdge_trbl] = isMouseOverRectangle();
        
        % debug
        %fprintf('Dwn state : %d, indx : %d\n',guiState,activeRectangleIndex)
        
        switch guiState,
            case GUI_STATES.INIT, 
                if leftClick,
                    guiState  = GUI_STATES.BROWSE_ABSPOS;
                elseif rightClick,
                end;
            case GUI_STATES.BROWSE_ABSPOS,
                error('Dwn 11 : Should not be here')
            case GUI_STATES.BROWSE_DIFFPOS,
                error('Dwn 12 : Should not be here')
            case GUI_STATES.ROI_INIT, 
                if leftClick,
                    if yesItIs,
                        activeRectangleIndex        = index;
                        % start editing : take ref point and rectagle
                        fManageRoiArray('copyFromList',activeRectangleIndex);
                        guiState  = GUI_STATES.ROI_SELECTED;
                    else 
                        % start drawing
                        fManageLastRoi('init',0);
                        fManageLastRoi('setTInd',activeTimeIndex);
                        guiState  = GUI_STATES.ROI_DRAW;
                    end
                elseif rightClick,
                end;
                
                
            case {GUI_STATES.ROI_DRAW}
                error('Dwn 2 : Should not be here')
            case GUI_STATES.ROI_SELECTED,
                % return roi back if any and selecte new if it is on
                if activeRectangleIndex < 1,
                    error('Dwn 3 : DBG : activeRectangleIndex must be positive')
                end
                
                if leftClick,
                    if yesItIs,
                        % new roi selected
                        if activeRectangleIndex  ~= index,
                            % return back and extract new current roi
                            fManageRoiArray('copyToList',activeRectangleIndex);
                            %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);
                            activeRectangleIndex  = index;
                            fManageRoiArray('copyFromList',activeRectangleIndex);
                        end
                        % clicked on the same ROI :  inside or edge
                        if isEdge,
                            guiState  = GUI_STATES.ROI_EDIT;
                        else
                            guiState  = GUI_STATES.ROI_MOVE;
                        end;
                        % take new RefPoint and RefRectangle
                        %activeRectangleIndex  = index;
                        %fManageRoiArray('copyFromList',activeRectangleIndex);
                        
                    else 
                        % clicked on the empty space
                        fManageRoiArray('copyToList',activeRectangleIndex);
                        %fSyncSend(Par.EVENT_TYPES.UPDATE_ROI);
                        guiState  = GUI_STATES.ROI_INIT;

                    end    
                elseif rightClick,
                    % Do nothing - may access the context menu
                    guiState = GUI_STATES.ROI_SELECTED;
                end;
                        
            case  GUI_STATES.PLAYING,
                % stay there
                
            case GUI_STATES.ROI_MOVEALL, 
                % catch the closest moviePoint
                if leftClick,
                    fManageReferencePoints('closest',point1(1,1:2));
                end
                
                
            otherwise
               % error('bad roi state')
        end
        
        %fRefreshImage();
        
        
    end

    function hFigure_UpFcn(~, ~)
        
        % debug
        %fprintf('Up  state : %d, indx : %d\n',guiState,activeRectangleIndex)
        
        
        switch guiState,
          case GUI_STATES.INIT, 
                % no ROi selected
                %error('Up 1 should not be here')
             
          case GUI_STATES.BROWSE_ABSPOS,
                if leftClick, % add roi to list
                    % if size of the roi is small  - it is not added - just like click outside
                    fUpdateBrowseData();
                    % Sync other GUIs
                    %fSyncSend();
                    guiState  = GUI_STATES.INIT;
                elseif rightClick, % show context menu
                 end;
          case GUI_STATES.BROWSE_DIFFPOS,
                    guiState  = GUI_STATES.INIT;
            case GUI_STATES.ROI_INIT, 
                % no ROi selected
                %error('Up 1 should not be here')
                activeRectangleIndex = -1;
                %set(handStr.roiFig, 'pointer',pointer);
                
            case GUI_STATES.ROI_DRAW,
                if leftClick, % add roi to list
                    % if size of the roi is small  - it is not added - just like click outside
                     switch roiLast.Type,
                         case ROI_TYPES.RECT,
                         case ROI_TYPES.ELLIPSE,
                         case ROI_TYPES.FREEHAND,
                             % make it closed
                            xData                   = get(roiLast.XY.hShape,'xdata');
                            yData                   = get(roiLast.XY.hShape,'ydata');
                            %rectangleInitialPosition = roiLast.Position; % no scaling
                            fManageLastRoi('addPoint',[xData(1) yData(1)]);
                     end;
                     
                     % protect from small touch
                     if prod(roiLast.Position(3:4)) < 50,
                        fManageLastRoi('clean',0); 
                        guiState  = GUI_STATES.ROI_INIT;
                     else
                        fManageRoiArray('add',0);                
                        guiState  = GUI_STATES.ROI_SELECTED;
                     end
                    
                elseif rightClick, % show context menu
                    %guiState  = GUI_STATES.INIT;
                    
                end;
               
            case GUI_STATES.ROI_SELECTED,
                if leftClick, % add roi to list
                 elseif rightClick, % show context menu
                    %guiState  = GUI_STATES.ROI_INIT;
                end;
                roiIsBeingEdited = true;  % update ROI info entirely

            case GUI_STATES.ROI_EDIT,
                if leftClick, % add roi to list
                 elseif rightClick, % show context menu
                end;
                %fManageRoiArray('copyToList',activeRectangleIndex);                
                guiState  = GUI_STATES.ROI_SELECTED;
             
            case GUI_STATES.ROI_MOVE,
                if leftClick, % add roi to list
                 elseif rightClick, % show context menu
                end;
                %fManageRoiArray('copyToList',activeRectangleIndex);                
                guiState  = GUI_STATES.ROI_SELECTED;
               
            case  GUI_STATES.PLAYING,
                % stay there
                
            case GUI_STATES.ROI_MOVEALL, 
                % catch the closest moviePoint
                if leftClick,
                    fManageReferencePoints('release',0);
                end
                
            otherwise
                %error('bad roi state')
        end

        
        fRefreshImage();
        leftClick  = false;
        rightClick = false;
    end

%-----------------------------------------------------
% Keyboard

    function hFigure_KeyPressFcn(~,eventdata)
        
%         if guiState  == GUI_STATES.ROI_MOVEALL,
%             switch eventdata.Key,
%                 case 'rightarrow', clickedNavToolPos (0, 0, 1, 0);
%                 case 'leftarrow',  clickedNavToolPos (0, 0,-1, 0);
%                 case 'uparrow',    clickedNavToolPos (0, 0, 0,-1);
%                 case 'downarrow',  clickedNavToolPos (0, 0, 0, 1);
%                 otherwise
%             end
%             
%         else
            switch eventdata.Key
                case 'delete'
                    fRefreshImage();
                case 'backspace',
                    fRefreshImage();
                case 'rightarrow', clickedNavToolT (0, 0, 1);
                case 'leftarrow',  clickedNavToolT (0, 0,-1);
                case 'uparrow',    clickedNavToolT (0, 0, 10);
                case 'downarrow',  clickedNavToolT (0, 0,-10);
                    
                otherwise
            end
%        end
    end

%-----------------------------------------------------
% Button Clicks

    function clickedHelpTool(~, ~)
        %reached when user click HELP button
        heltTxt{1} = sprintf('TwoPhoton : Video file name    %s',     Par.DMT.VideoFileNames{Par.DMT.Trial});
        heltTxt{2} = sprintf('Behavior  : Video Front file name   %s',Par.DMB.VideoFrontFileNames{Par.DMB.Trial});
        heltTxt{3} = sprintf('Behavior  : Video Side  file name   %s',Par.DMB.VideoSideFileNames{Par.DMB.Trial});
        helpdlg(heltTxt)
    end

    function clickedNavToolT (~, ~, incr)
        
        % check update
        if abs(incr) < 1, return; end;
        activeTimeIndex = max(1,min(activeTimeIndex + round(incr),nT));
        fSyncSend(EVENT_TYPES.UPDATE_POS);
        %fRefreshImage()
    end

    function clickedNavToolXY (~, ~, incr)
        
        if abs(incr) < 1, return; end;        
        activeXaxisIndex = max(1,min(activeXaxisIndex + round(incr),nC));               
        fSyncSend(EVENT_TYPES.UPDATE_POS);
        %fComputeImageForShow();      
        %fRefreshImage()
    end

    function clickedNavToolZ (~, ~, incr)
        
        if abs(incr) < 1, return; end;        
        activeZstackIndex = max(1,min(activeZstackIndex + round(incr),nZ));               
        %fSyncSend(EVENT_TYPES.UPDATE_IMAGE);
        %fSyncSend(EVENT_TYPES.UPDATE_ROI);
        fSyncSend(EVENT_TYPES.UPDATE_POS);
        %fComputeImageForShow();      
        %fRefreshImage()
    end

    function clickedSliderToolT (~,~)
        % slider movements
        v       = get(handStr.timeSlideTool,'value');
        incr    = round(v) - activeTimeIndex;
        clickedNavToolT (0, 0, incr);
    end

    function clickedNavToolPos (~, ~, incrX,incrY)
        
        if abs(incrX) < 1 && abs(incrY) < 1, return; end;                
        fManageRoiArray('updatePos',[incrX,incrY]);
        %fSyncSend(EVENT_TYPES.UPDATE_POS);
        %fComputeImageForShow();      
        fRefreshImage()
    end

    function clickedPlayTool()
        % plays movie
        fdelay  = Par.PlayerMovieTime/nT; % delay between frames
        incr    = ceil(0.1/fdelay);       % skip frames if frame delay is below 100 msec
        %incr    = Par.Player.FrameInrement;
        %fdelay  = Par.Player.FrameDelay;
        while guiState  == GUI_STATES.PLAYING,
            clickedNavToolT (0, 0, incr);
            pause(fdelay);
            if activeTimeIndex == nT, break; end;
        end
 
    end

    function clickedToolButton (~, ~, buttonType)
        % state management
        
        %set([handStr.rectangleTool , handStr.ellipseTool , handStr.freehandTool ,  handStr.browseTool],'State', 'off')
        set(handStr.ellipseTool,    'State', 'off');
        set(handStr.rectangleTool,  'State', 'off');
        set(handStr.freehandTool,   'State', 'off');
        %set(handStr.moveAllTool,    'State', 'off');
        %set(handStr.hideAllTool,    'State', 'off');
        set(handStr.browseTool,     'State', 'off');
        set(handStr.playerTool,     'State', 'off');
        switch buttonType,
            case BUTTON_TYPES.RECT,
                    set(handStr.rectangleTool,  'State', 'on');
                    guiState  = GUI_STATES.ROI_INIT;
            case BUTTON_TYPES.ELLIPSE
                    set(handStr.ellipseTool,    'State', 'on');
                     guiState  = GUI_STATES.ROI_INIT;
           case BUTTON_TYPES.FREEHAND
                    set(handStr.freehandTool,   'State', 'on');
                     guiState  = GUI_STATES.ROI_INIT;
           case BUTTON_TYPES.BROWSE
                    set(handStr.browseTool,   'State', 'on');
                     guiState  = GUI_STATES.INIT;
            case BUTTON_TYPES.MOVEALL,
                    if strcmp('on',get(handStr.moveAllTool,   'State')),
                        fManageReferencePoints('init',0);
                        fManageReferencePoints('saveRoiPos',0);
                        guiState  = GUI_STATES.ROI_MOVEALL;
                    else
                        fManageReferencePoints('recallRoiPos',0);
                        fManageReferencePoints('clean',0);
                        guiState  = GUI_STATES.INIT;
                    end
                    fRefreshImage();
            case BUTTON_TYPES.HIDEALL, % does not change the state
                    hideAllNames = strcmp('on',get(handStr.hideAllTool,   'State'));
                    fRefreshImage();
            case BUTTON_TYPES.PLAYER,
                    if guiState  == GUI_STATES.PLAYING,
                        guiState  = GUI_STATES.INIT;
                        set(handStr.playerTool,   'State', 'off', 'CData',handStr.ico.player_play);
                    else
                        guiState  = GUI_STATES.PLAYING;
                        set(handStr.playerTool,   'State', 'on', 'CData',handStr.ico.player_stop);
                        clickedPlayTool();
                        guiState  = GUI_STATES.INIT;
                        set(handStr.playerTool,   'State', 'off', 'CData',handStr.ico.player_play);
                   end
                
           otherwise
                % nothing is sellected
                error('Unknown  buttonType %d',buttonType)
        end
        % last clicked position
        buttonState = buttonType;

        
        %fprintf('Tool  state : %d, pointer : %s\n',guiState,pointer)

        %fRefreshImage()
    end

%-----------------------------------------------------
% GUI Image management

   function fUpdateBrowseData()
       
       % check if the button browse is pressed
        if guiState ~= GUI_STATES.BROWSE_ABSPOS, return; end
       
        % manage increment of image browse T on YT GUI and X on XY GUI
        units = get(handStr.imgAxes,'units');
        set(handStr.imgAxes,'units','normalized');
        point2 = get(handStr.imgAxes, 'CurrentPoint');
        set(handStr.imgAxes,'units',units);
        
        % who am I :  act accordingly
        switch guiType,
           case {Par.GUI_TYPES.TWO_PHOTON_XY,Par.GUI_TYPES.BEHAVIOR_XY} % each new point will be absolute position
                xMouse      = (point2(1,1)) - activeXaxisIndex;
                clickedNavToolXY(0,0,xMouse)
           case {Par.GUI_TYPES.TWO_PHOTON_YT,Par.GUI_TYPES.BEHAVIOR_YT} % each new point will be absolute position
                xMouse      = (point2(1,1)) - activeTimeIndex;
                clickedNavToolT(0,0,xMouse)
            otherwise
                error('Bad guiType')
       end
        %fprintf('updateBrowseData : %5.2f\n',velT)
    end

   function fUpdateImageShow(~, ~, menuImageType)
       % function handles image preprocessing type and gui indications
       % 
       set(handStr.menuImage(2:end),'checked','off');
       % save for performance
       
        %set([handStr.rectangleTool , handStr.ellipseTool , handStr.freehandTool ,  handStr.browseTool],'State', 'off')
        switch menuImageType,
            case IMAGE_TYPES.RAW,
               set(handStr.menuImage(2),'checked','on')
               imageShowState    = IMAGE_TYPES.RAW;
            case IMAGE_TYPES.MEAN,
               set(handStr.menuImage(3),'checked','on')
               imageShowState    = IMAGE_TYPES.MEAN;
           case IMAGE_TYPES.MAX,
               set(handStr.menuImage(4),'checked','on')
               imageShowState    = IMAGE_TYPES.MAX;
         case IMAGE_TYPES.GRADT,
               set(handStr.menuImage(5),'checked','on')
               imageShowState    = IMAGE_TYPES.GRADT;
         case IMAGE_TYPES.GRADXY,
               set(handStr.menuImage(6),'checked','on')
               imageShowState    = IMAGE_TYPES.GRADXY;
         case IMAGE_TYPES.STD,
               set(handStr.menuImage(7),'checked','on')
               imageShowState    = IMAGE_TYPES.STD;
         case IMAGE_TYPES.DFF,
               set(handStr.menuImage(8),'checked','on')
               imageShowState    = IMAGE_TYPES.DFF;
            otherwise error('bad menuImageType')
        end
        
        %activeIndexFixed(3) = false;  % informs image processing to do update
        fComputeImageForShow();
        %fRefreshImage()
        
   end

   function fComputeImageForShow()
       % function computes image presented to the user
       % 
                 
       
       % do not compute all updates
       stateIsChanged = imagePrevState ~= imageShowState;
           
           
       % NEED TO MAKE IT NICE
       
        switch imageShowState,
            case IMAGE_TYPES.RAW,
               %if all(activeIndexFixed(3:4)), return; end; % improve performance
               if previousXYZTIndex(3) ~= activeZstackIndex || previousXYZTIndex(4) ~= activeTimeIndex || stateIsChanged,
               imageIn           = squeeze(SData.imTwoPhoton(:,:,activeZstackIndex,activeTimeIndex));
               end
            case IMAGE_TYPES.MEAN,
               %if any(activeIndexFixed(3)), return; end; % improve performance
               if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged,
               imageIn           = squeeze(mean(SData.imTwoPhoton(:,:,activeZstackIndex,:),4));
               end
           case IMAGE_TYPES.MAX,
              if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged, 
               %if any(activeIndexFixed(3)), return; end; % improve performance
               imageIn           = squeeze(max(SData.imTwoPhoton(:,:,activeZstackIndex,:),[],4));
              end
            case IMAGE_TYPES.GRADT,
              if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged, 
              DTP_ManageText([], sprintf('Computing Image transformation. Please wait....'), 'I' ,0);                
               %if any(activeIndexFixed(3)), return; end; % improve performance
               imageIn           = squeeze(mean(abs(SData.imTwoPhoton(:,:,activeZstackIndex,2:nT-1)*2 - ...
                                                   SData.imTwoPhoton(:,:,activeZstackIndex,3:nT) - ....
                                                   SData.imTwoPhoton(:,:,activeZstackIndex,1:nT-2)),4));
               DTP_ManageText([], sprintf('Done.'), 'I' ,0);
              end
           case IMAGE_TYPES.GRADXY,
               %if any(activeIndexFixed(3)), return; end; % improve performance
               if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged, 
               DTP_ManageText([], sprintf('Computing Image transformation. Please wait....'), 'I' ,0);                
               imageIn          = squeeze(mean(abs(SData.imTwoPhoton(2:nR-1,2:nC-1,activeZstackIndex,:)*2 - ...
                                                  SData.imTwoPhoton(1:nR-2,2:nC-1,activeZstackIndex,:) - ...
                                                  SData.imTwoPhoton(2:nR-1,1:nC-2,activeZstackIndex,:)),4));
               imageIn           = imageIn([1 1:nR-2 nR-2],[1 1:nC-2 nC-2]); % borders
                DTP_ManageText([], sprintf('Done.'), 'I' ,0);
               end
            case IMAGE_TYPES.STD,
               %if any(activeIndexFixed(3)), return; end; % improve performance
               if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged, 
               imageInTmp        = single(squeeze(SData.imTwoPhoton(:,:,activeZstackIndex,:)));
               imageIn           = std(imageInTmp,[],3);
               end
            case IMAGE_TYPES.DFF,
               % almost dff
               if previousXYZTIndex(3) ~= activeZstackIndex || stateIsChanged, 
               DTP_ManageText([], sprintf('Computing Image transformation. Please wait....'), 'I' ,0);                
               imageInTmp        = single(squeeze(SData.imTwoPhoton(:,:,activeZstackIndex,:)));
               filtH             = ones(3,3,5)/45;
               imageInTmp        = imfilter(imageInTmp,filtH);
               imageInMean       = mean(imageInTmp,3);
               %imageInStd         = mean(imageInTmp,3);
               %imageInStd        = std(imageInTmp,[],3)+10;
               DTP_ManageText([], sprintf('Done.'), 'I' ,0);
               end
               
               %imageIn           = max(bsxfun(@minus,imageInTmp,imageInMean)./repmat(imageInStd,[1,1,nT]),[],3);
               imageIn           = single(SData.imTwoPhoton(:,:,activeZstackIndex,activeTimeIndex));
               imageIn           = (imageIn - imageInMean)./imageInMean;
               % remove shot noise
               %imageInBool       = imageIn < 1;
               %imageIn(imageInBool) = imageIn(imageInBool).*.1;
               
            otherwise error('bad menuImageType')
        end
        % save
        previousXYZTIndex       = [activeXaxisIndex activeYaxisIndex activeZstackIndex activeTimeIndex];
        imagePrevState          = imageShowState;

        fRefreshImage()
        
   end

   function fRefreshImage (~)
        %Refresh the image & plot
        
        if guiIsBusy, return; end;
        guiIsBusy = true;
        
        axes(handStr.imgAxes);
        set(handStr.imgShow,'cdata',imageIn);
        set(handStr.imgText,'string',sprintf('X:%3d/%3d, Y:%3d/%3d, Z:%2d/%2d, T:%4d/%4d',activeXaxisIndex,nC,activeYaxisIndex,nR,activeZstackIndex,nZ,activeTimeIndex,nT))
        set(handStr.imgNav,'xdata',ones(2,1)*activeXaxisIndex);
        
        %activeIndexFixed(:) = true; % designate that we did it
        
        % in case when control is outside window
        set(handStr.timeSlideTool,'value',activeTimeIndex);
        
        %sz = size(roiSelection,2);
        sz = length(SData.strROI);
        for i=1:sz
            
            % protect when strROI is intialized partially
            if ~isfield(SData.strROI{i},'XY'), 
                continue; 
            end
            % one view protect
            if ~isfield(SData.strROI{i}.XY,'hBoundBox'), 
                continue; 
            else
                if ~ishandle(SData.strROI{i}.XY.hBoundBox), 
                    continue
                end
            end
            
            % default controls
            color           = 'y';
            showBox         = 'off';
            showRoi         = 'on';    
            showTxt         = 'on';
            
            if i==activeRectangleIndex
                color       = 'r';
                showBox     = 'on';
            end
                
            if SData.strROI{i}.zInd ~= activeZstackIndex,
                showRoi     = 'off';
                showTxt     = 'off';
                showBox     = 'off';
            end
            if hideAllNames,
                showTxt     = 'off';
            end
            
            % special state of the tool
            switch guiState,
                case GUI_STATES.ROI_MOVEALL,
            end
            
            
            
            %pos                     = SData.strROI{i}.Position;
            %xy                      = repmat(pos(1:2),5,1) + [0 0;pos(3) 0;pos(3) pos(4); 0 pos(4);0 0];
            %set(SData.strROI{i}.XY.hShape,     'xdata',xy(:,1),'ydata',xy(:,2),'Color',color);
            %set(SData.strROI{i}.XY.hShape,     'position',SData.strROI{i}.Position, 'edgeColor',color);
            set(SData.strROI{i}.XY.hShape,    'visible',showRoi,'Color',color);
            set(SData.strROI{i}.XY.hText,     'visible',showTxt,'Color',color);
            set(SData.strROI{i}.XY.hBoundBox,  'visible',showBox,'edgeColor',color);
            set(SData.strROI{i}.XY.hCornRect,  'visible',showBox,'Color',color); 
            % all the active rectangles - hide
            %set(SData.strROI{i}.XY.hCornRect, 'visible','off');

            
            %if strcmp(color,'r')
                %draw small squares in the corner and middle of length
                %set(SData.strROI{i}.XY.hBoundBox,  'visible',showBox,'edgeColor',color);
                %set(SData.strROI{i}.XY.hText,      'visible',showRoi,'Color',color);
                %set(SData.strROI{i}.XY.hCornRect,  'visible',showBox,'Color',color);                
                
            %end
            
        end
        
        guiIsBusy = false;
        
   end


%-----------------------------------------------------
% Reference point Management

   function fManageReferencePoints(Cmnd,Data)
        if nargin < 2, Data = 0; end;
        switch Cmnd,
            
            case 'init',
                
                roiAlignStr.fixedPoints             = [.2*nC .2*nR; .2*nC .8*nR; .8*nC .8*nR;.8*nC .2*nR];
                roiAlignStr.movingPoints            = roiAlignStr.fixedPoints;
                roiAlignStr.hFixed                  = [];
                roiAlignStr.hMove                   = [];
                roiAlignStr.strROI                  = {};
                roiAlignStr.activeInd               = -1;   %whci point being dragged
                 
                fManageReferencePoints('initView',0);
                
            case 'clean', 
                
                % remove the points
                delete(roiAlignStr.hFixed);
                delete(roiAlignStr.hMove);
                roiAlignStr.strROI                  = {};
                roiAlignStr.activeInd               = -1;
                
                
            case 'closest',
                
                % data contains x and y pointer info
                assert(numel(Data) == 2,'Pointer info must have 2 numbers x and y');
                % borders
                if Data(1) < 10 || Data(1) > nC-10, return; end;
                if Data(2) < 10 || Data(2) > nR-10, return; end;
                
                mPos                = roiAlignStr.movingPoints;
                distMove            = (mPos(:,1)-Data(1)).^2 + (mPos(:,2)-Data(2)).^2;
                [distMin,distInd]   = min(distMove);
                
                % 5 pixel distance - do nothing
                if distMin > 30,  return; end;
                
                roiAlignStr.activeInd = distInd;
                
                fManageReferencePoints('updateMove',Data);
                
            case 'release',
                
                % release current point
                roiAlignStr.activeInd  = -1;
                fManageReferencePoints('updateView',0);
                % The next lines makes ROI to appear from intial position and not from previous
                SData.strROI = roiAlignStr.strROI;                
                fManageReferencePoints('updateRoiPos',0);
                
            case 'updateMove',
                
                % do nothing
                if (numel(Data) ~= 2) ,Data = roiAlignStr.movingPoints(1,:); end;
                
                % borders
                if Data(1) < 10 || Data(1) > nC-10, return; end;
                if Data(2) < 10 || Data(2) > nR-10, return; end;
                if roiAlignStr.activeInd < 1, return; end
                
                % assign
                distInd         = roiAlignStr.activeInd;
                roiAlignStr.movingPoints(distInd,1) = Data(1);
                roiAlignStr.movingPoints(distInd,2) = Data(2);
                
                fManageReferencePoints('updateView',0);
                
                
            case 'saveRoiPos', 
                
                % saves current roi positions
                roiAlignStr.strROI  = SData.strROI;
                
            case 'recallRoiPos', 
                
                % recall last roi positions - dump all the changes
                buttonName = questdlg('Would you like to keep these changes in ROI positions? ');  
                if ~strcmp(buttonName,'Yes'),
                    SData.strROI = roiAlignStr.strROI;
                    return; 
                end;
                %roiNum             = length(SData.strROI);  
                
            case 'updateRoiPos', 
                
                % computes transforms and updates roi positions
                t_form = maketform('projective',roiAlignStr.fixedPoints,roiAlignStr.movingPoints);
                
                fManageRoiArray('updateTransform',t_form);

                
                
            case 'initView',

                % redraw all points in the same position
                if ~isempty(roiAlignStr.hFixed), 
                    fManageReferencePoints('clean',0); 
                end;
                
                hold on;
                roiAlignStr.hFixed  = plot(handStr.imgAxes,roiAlignStr.fixedPoints(:,1),roiAlignStr.fixedPoints(:,2),'om','MarkerSize',12);
                roiAlignStr.hMove   = plot(handStr.imgAxes,roiAlignStr.movingPoints(:,1),roiAlignStr.movingPoints(:,2),'.g','MarkerSize',16);
                hold off;
                

            case 'updateView',
                
                % do nothing
                 set(roiAlignStr.hMove,'xdata',roiAlignStr.movingPoints(:,1),'ydata',roiAlignStr.movingPoints(:,2));
                
            otherwise
                error('Unknown Cmnd : %s',Cmnd)

        end
   end


%-----------------------------------------------------
% GUI MultiWindow Synchronization

    function fSyncSend(eventId)
        % Update global data and call other gui elements to update
        % Called by internal functions
        if nargin < 1, eventId = Par.EVENT_TYPES.UPDATE_POS; end

        switch eventId,
            case Par.EVENT_TYPES.UPDATE_POS
                dataPos              = [activeXaxisIndex activeYaxisIndex activeZstackIndex activeTimeIndex];
                [SGui.usrInfo(srcId).posManager,msgObj]  = SGui.usrInfo(srcId).posManager.Encode(eventId,dataPos);
            case Par.EVENT_TYPES.UPDATE_ROI,
                return
                roiId                = 1; % TBD
                [SGui.usrInfo(srcId).roiManager,msgObj]  = SGui.usrInfo(srcId).roiManager.Encode(eventId,roiId);
            otherwise
        end

        %fprintf('XY fSyncSend %d : %d \n',srcId,eventId); %tic;
        
        % inform other gui elements
        feval(fSyncAll,srcId,msgObj);
    end

    function fSyncRecv(srcIdRx,msgObjRx)
       % this function is called by Main GUI only

        %fprintf('XY fSyncRecv %d : %d \n',srcIdRx,msgObjRx.msgId);
        
        updateRefreshImage = false;
        updateShowImage    = false;
        updateRoiArray     = false;
        
        
         switch msgObjRx.msgId,
            case Par.EVENT_TYPES.UPDATE_POS,
        
            % deal with position
             [SGui.usrInfo(srcId).posManager,msgObjRx]  = SGui.usrInfo(srcId).posManager.Decode(msgObjRx);
             if ~msgObjRx.skip,
                    dataPos           = round(msgObjRx.data);
                    activeXaxisIndex  = max(1,min(nC,dataPos(1)));
                    activeYaxisIndex  = max(1,min(nR,dataPos(2)));       
                    activeZstackIndex = max(1,min(nZ,dataPos(3)));
                    activeTimeIndex   = max(1,min(nT,dataPos(4)));

                    % call
                    %feval(msgObjRx.funCall{1})
                    %fRefreshImage();   
                    updateRefreshImage = updateRefreshImage || msgObjRx.updateRefreshImage;
                    updateShowImage    = updateShowImage || msgObjRx.updateShowImage;
             end
            case Par.EVENT_TYPES.UPDATE_ROI,
            % deal with ROI
             [SGui.usrInfo(srcId).roiManager,msgObjRx]  = SGui.usrInfo(srcId).roiManager.Decode(msgObjRx);
             if ~msgObjRx.skip,
                    roiId           = msgObjRx.data;

                    % call
                    %feval(msgObjRx.funCall{1})
                    %fRefreshImage();   
                    updateRoiArray      = updateRoiArray || msgObjRx.updateRoiArray;
                    updateRefreshImage  = updateRefreshImage || msgObjRx.updateRefreshImage;
             end
         end
         
%       somtimes it intensive
        if updateShowImage,
            % compute image
            fComputeImageForShow();
        end
%         
        % update ROIs
        if updateRoiArray,
            %fManageRoiArray('createView');
            fManageRoiArray('updateView');
        end
        
        % update ROI, Pos, Image on Display
        if updateRefreshImage,
            fRefreshImage();
        end
    end

%-----------------------------------------------------
% Finalization

    function fCloseRequestFcn(~, ~)
        % This is where we can return the ROI selected
        
        % check the state - could be ROI changes
        if guiState  == GUI_STATES.ROI_MOVEALL,
            fManageReferencePoints('recallRoiPos',0);
            fManageReferencePoints('clean',0);
        end
        
        fExportROI();               % check that ROI structure is OK
        
        %uiresume(handStr.roiFig);
        try
            % remove from the child list
            ii = find(SGui.hChildList == handStr.roiFig);
            SGui.hChildList(ii) = [];
            delete(handStr.roiFig);
        catch ex
            errordlg(ex.getReport('basic'),'Close Window Error','modal');
        end
       % return attention
       figure(SGui.hMain)
    end

%-----------------------------------------------------
% Helpers

    function xy = PosToRect(pos)
        % Helper function that transforms position to corner rectangles
        xy =  [ pos(1:2);...
            pos(1:2)+[0 pos(4)/2];...
            pos(1:2)+[0 pos(4)];...
            pos(1:2)+[pos(3)/2 pos(4)];...
            pos(1:2)+[pos(3) pos(4)];...
            pos(1:2)+[pos(3) pos(4)/2];...
            pos(1:2)+[pos(3) 0];...
            pos(1:2)+[pos(3)/2 0];...
            pos(1:2)];

    end


end
