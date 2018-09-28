% control_acbar: control software for ACBAR electrodynamic balance
%
% originally developed in Huisman Lab, Union College
% adapted in Keutsch Lab, Harvard University
%
% dependencies:
%   DS345Device.m : Matlab class for serial communication with function
%                   generator
%   injector.ino : Arduino script for droplet injection pulse generation
%
% commands to shut down program before restarting:
% >> close all
% >> delete(instrfind)
% >> delete(timerfind)
% >> imaqreset

function control_acbar()
%% define 'global' parameters (within controL_acbar() scope)
FULLRANGE_DC = 830; % V

%% create acbar_main window
main = figure('visible','off',...
    'Name','acbar_main',...
    'Position',[50,600,300,210],...
    'MenuBar','none',...
    'ToolBar','none');

set(main,'visible','on');
delete(timerfindall);

%% build buttons and displays
save_checkbox = uicontrol('parent',main,'style','checkbox',...
    'string','Save data to file',...
    'value',0,'position',[10 30 140 20],'tag','save_checkbox');

% info next to save_checkbox spills over to second line, but checkbox
% uicontrol can only contain single line
uicontrol('parent',main,'style','text',...
    'string','(in Documents\acbar_data\)','position',[28 15 140 15],...
    'HorizontalAlignment','left');

save_filename = uicontrol('parent',main,'style','edit',...
    'string','Enter filename here',...
    'position',[10 60 140 20],...
    'callback',@checkfile_exist,...
    'tag','save_filename');

fasttimer_button = uicontrol(main,...
    'style','togglebutton','value',0,...
    'position',[10 150 150 20],...
    'string','Start background timer',...
    'callback',@fasttimer_startstop,...
    'tag','fasttimer_button');

errorcatchtimer_button = uicontrol(main,...
    'style','togglebutton','value',0,...
    'position',[10 180 150 20],...
    'string','Start error catch timer',...
    'callback',@errortimer_startstop,...
    'tag','errorcatchtimer_button');

MKSscramcomms = uicontrol(main,'style','pushbutton',...
    'position',[175 45 110 20],'string','SCRAM COMMS',...
    'callback',@SCRAM_COMMS,'tag','scramcomms');

flush_button = uicontrol(main,'style','pushbutton',...
    'position',[175 20 110 20],'string','Flush All Data',...
    'callback',@flush_data,'tag','flush_button');

% build checkboxes to toggle window visibility
uicontrol(main,'style','text','string','Window visibility',...
    'position',[160 185 100 20]);
% give checkboxes tags like 'microscope_checkbox', etc., and have them
% toggle visibility of windows with tags like 'microscope_window'
labels = {'microscope','fringe','arduino','mks','andor','hygrometer'};
% startup visibility of each window, used to set both initial checkbox
% state as well as the actual visibility in build_fringe_window, etc.
window_visibility_default = [1,1,1,1,0,0];
for i = 1:6
    % generate tag for new checkbox
    checkbox_tag = strcat(labels{i},'_checkbox');
    % assume same tag prefix for window whose visibility is toggled
    window_tag = strcat(labels{i},'_window');
    % generate actual checkbox uicontrol object
    uicontrol('parent',main,...
        'style','checkbox',...
        'string',labels{i},...
        'value',window_visibility_default(i),...
        'position',[175 170-20*(i-1) 140 20],...
        'callback',{@toggle_window_visibility,window_tag},...
        'tag',checkbox_tag,...
        'visible','on');
end

fastupdatetext = uicontrol(main,'style','text',...
    'string','Fast update: 0.??? s',...
    'position',[10 110 150 15],...
    'tag','fastupdatetext');

slowupdatetext = uicontrol(main,'style','text',...
    'string','Slow update at ??:??:??',...
    'position',[10 80 150 15],...
    'tag','slowupdatetext');

%% Initialize main window
fasttimer = timer('TimerFcn',@fasttimerFcn,'ExecutionMode','fixedRate',...
    'Period',0.10);

errorcatchtimer = timer('TimerFcn',@errorcatchFcn,...
    'ExecutionMode','fixedRate','Period',30);


%set Flags for camera
setappdata(main,'camera1Flag',0)
setappdata(main,'camera2Flag',0)
setappdata(main,'FrameNumber',0);
setappdata(main,'UPSInumber',1); %default to sensor 1
setappdata(main,'AndorFlag',0);
setappdata(main,'AndorImage',[]);
setappdata(main,'AndorTimestamp',[]);
setappdata(main,'AndorImage_startpointer',0);
setappdata(main,'AndorCalPoly',[]);
setappdata(main,'VoltageData',[]);
setappdata(main,'UPSIdata',[]);
setappdata(main,'RampFlag',0);
setappdata(main,'MKSdatalog',[]);
setappdata(main,'Laudadatalog',[]);
setappdata(main,'Julabodatalog',[]);
setappdata(main,'fringe_timestamp',[]);
setappdata(main,'fringe_compressed',[]);
setappdata(main,'image_timestamp',[]); %timestamp for images
setappdata(main,'fringe_image',[]);
setappdata(main,'microscope_image',[]);
setappdata(main,'hygrometer_data',[]);
setappdata(main,'voltage_data_nofeedback',[]);
% set trap voltages and frequencies to -1 before initialization
setappdata(main,'voltage_dc_trap',-1);
setappdata(main,'amp_ac_trap',-1);
setappdata(main,'freq_ac_trap',-1);

% initialize *****_window_handle vars in control_acbar()'s scope.
% the `build_*****_window` functions, as nested functions, then share the
% same *****_window_handle variables! See:
% https://www.mathworks.com/help/matlab/matlab_prog/nested-functions.html
microscope_window_handle = [];
fringe_window_handle = [];
arduino_window_handle = [];
MKS_window_handle = [];
Andor_window_handle = [];
hygrometer_window_handle = [];

build_microscope_window(window_visibility_default(1));
build_fringe_window(window_visibility_default(2));
build_arduino_window(window_visibility_default(3));
build_MKS_window(window_visibility_default(4));
build_Andor_window(window_visibility_default(5));
build_hygrometer_window(window_visibility_default(6));

    function checkfile_exist(source,eventdata)
        % TODO add code to make sure filename just typed in does not already
        % exist in the folder. This will present accidental overwrite of data!
        value = source.String;
        if(exist([value '.mat'],'file')==2)
            source.String = 'choose a new file name';
        end
    end

%% functions that build windows and initialize variables
    function build_microscope_window(visibility)
        microscope_window_handle = figure('visible','off',...
            'Name','microscope',...
            'Position',[500,500,900,300],...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'microscope_window');
        if visibility==1
            set(microscope_window_handle,'visible','on')
        end

        
        %create a button that arms the camera
        marm = uicontrol(microscope_window_handle,'style','togglebutton',...
            'String','Run Camera',...
            'Value',0,'position',[10 100 100 20],...
            'Callback',@microscope_camera_arm,'tag','marm');
        
        %create a static text box to show camera status
        mstatus_display = uicontrol(microscope_window_handle,'style','text',...
            'string','Camera Status',...
            'position',[120 90 50 30],...
            'tag','mstatus_display');
        set(mstatus_display,'backgroundcolor',[1 1 0]);
        
        %create slider for gain
        mgain_slider = uicontrol(microscope_window_handle,'style','slider',...
            'min',0,'max',18,'value',2,...
            'sliderstep',[0.01 0.2],...
            'position',[10 70 100 20],...
            'Callback',@change_microscope_gain,...
            'tag','mgain_slider');
        
        %create a static text to show camera gain
        mgain_display = uicontrol(microscope_window_handle,'style','text',...
            'string',[num2str(get(mgain_slider,'value'),'%2.1f') ' dB'],...
            'position',[120 70 50 15],...
            'tag','mgain_display');
        
        %create slider for shutter
        mshutter_slider = uicontrol(microscope_window_handle,'style','slider',...
            'min',0.011,'max',33.2,'value',1,...
            'sliderstep',[0.001 0.2],...
            'position',[10 40 100 20],...
            'Callback',@change_microscope_shutter,...
            'tag','mshutter_slider');
        
        %create a static text to show camera shutter
        mshutter_display = uicontrol(microscope_window_handle,'style','text',...
            'string',[num2str(get(mgain_slider,'value')) ' ms'],...
            'position',[120 40 50 15],...
            'Callback',@change_microscope_shutter,...
            'tag','mshutter_display');
        
        mfullscreen_button = uicontrol(microscope_window_handle,'style','pushbutton',...
            'string','Full Screen',...
            'position',[10 10 100 20],...
            'Callback',@microscope_fullscreen,...
            'tag','mfullscreen_button');
        
        %create a tab group for voltage plot
        tgroup1 = uitabgroup('parent',microscope_window_handle,...
            'position',[0.21 0.05 0.4 0.9],...
            'tag','tgroup1');
        tg1t1 = uitab('parent',tgroup1,'Title','Microsope',...
            'tag','tg1t1');
        tg1t2 = uitab('parent',tgroup1,'Title','Voltage Plot',...
            'tag','tg1t2');
        
        %create the axes for the microscope camera
        ax1 = axes('parent',tg1t1,'tag','ax1');
        set(ax1,'xticklabel',[]);
        set(ax1,'xtick',[]);
        set(ax1,'yticklabel',[]);
        set(ax1,'ytick',[]);
        %set the axes to not reset plot propertes
        set(ax1,'nextplot','add');
        set(ax1,'ydir','reverse');
        set(ax1,'xlim',[0 640],'ylim',[0 480])
        set(ax1,'Unit','normalized','Position',[0 0 1 1])
        
        %create the axes for the voltage display
        ax20 = axes('parent',tg1t2,'tag','ax20');
        set(ax20,'nextplot','replacechildren');
        set(ax20,'xlimmode','auto')
        
        midealy_label = uicontrol(microscope_window_handle,'style','text',...
            'position',[10 220 100 20],'horizontalalignment','center',...
            'string','y-axis set point',...
            'tag','midealy_label');
        
        midealy = uicontrol(microscope_window_handle,'style','edit',...
            'position',[10 200 100 20],'string','480',...
            'callback',@setidealY,...
            'tag','midealy');
        
        setappdata(main,'IdealY',480);
        
        midealy_get = uicontrol(microscope_window_handle,'style','pushbutton',...
            'callback',@getidealy,...
            'position',[115 200 50 20],'string','get','enable','off',...
            'tag','midealy_get');
        
        mhold_position = uicontrol(microscope_window_handle,'style','togglebutton',...
            'string','Hold Position',...
            'position',[10 160 100 20],...
            'callback',@mholdposition,...
            'tag','mhold_position');

        mhold_rescale_ac = uicontrol(microscope_window_handle,...
            'style','checkbox',...
            'string','rescale AC',...
            'position',[110 160 73 20],...
            'tag','mhold_rescale_ac');
        
        ax1clear = uicontrol(microscope_window_handle,'style','pushbutton','string','cla(ax1)',...
            'position',[10 130 100 20],...
            'callback',{@clearaplot,ax1},...
            'tag','uicontrol');
        
        initialize_microscope_variables();
        
        %build SRS control
        %check which serial ports are available
        serialinfo = instrhwinfo('serial');
        
        SRS2label = uicontrol(microscope_window_handle,'style','text',...
            'String','AC Fcn Generator',...
            'position',[570 220 90 15],...
            'tag','SRS2label');
        
        SRS2selectbox = uicontrol(microscope_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[665 220 100 20],...
            'tag','SRS2selectbox');
        
        SRS2openclose = uicontrol(microscope_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[775 220 100 20],...
            'callback',@srscomms,...
            'tag','SRS2openclose');
        
        
        DClabel = uicontrol(microscope_window_handle,'style','text',...
            'string','DC OFFS',...
            'Position',[550 195 100 20],...
            'tag','DClabel');
        
        DCOFFS = uicontrol(microscope_window_handle,'style','text',...
            'string','??? V ','position',[550 180 100 20],...
            'tag','DCOFFS');

        DCOFFS_plus10 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 160 80 20],'string','+10',...
            'callback',{@increment_dc,10},'tag','DC OFFS +10',...
            'enable','off');
        
        DCOFFS_plus1 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 130 80 20],'string','+1',...
            'callback',{@increment_dc,1},'tag','DC OFFS +1',...
            'enable','off');
        
        DCOFFS_plus01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 100 80 20],'string','+0.1',...
            'callback',{@increment_dc,0.1},'tag','DC OFFS +0.1',...
            'enable','off');
        
        DCOFFS_less01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 70 80 20],'string','-0.1',...
            'callback',{@increment_dc,-0.1},'tag','DC OFFS -0.1',...
            'enable','off');
        
        DCOFFS_less1 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 40 80 20],'string','-1',...
            'callback',{@increment_dc,-1},'tag','DC OFFS -1',...
            'enable','off');
        
        DCOFFS_less10 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[550 10 80 20],'string','-10',...
            'callback',{@increment_dc,-10},'tag','DC OFFS -10',...
            'enable','off');

        DCOFFS_set0 = uicontrol(microscope_window_handle,...
            'style','pushbutton',...
            'position',[750 55 80 20],...
            'string','set DC 0',...
            'callback',@zero_dc,'tag','DCOFFS_set0',...
            'enable','off');
        
        %% AC freq
        
        ACFREQlabel = uicontrol(microscope_window_handle,'style','text',...
            'string','AC FREQ',...
            'Position',[650 195 100 20],...
            'tag','ACFREQlabel');
        
        ACFREQ = uicontrol(microscope_window_handle,'style','text',...
            'string','??? Hz','position',[650 180 100 20],...
            'tag','ACFREQ');
        
        ACFREQ_plus10 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 160 80 20],'string','+10',...
            'callback',{@increment_ac_freq,10},'tag','AC FREQ +10',...
            'enable','off');
        
        ACFREQ_plus1 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 130 80 20],'string','+1',...
            'callback',{@increment_ac_freq,1},'tag','AC FREQ +1',...
            'enable','off');
        
        ACFREQ_plus01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 100 80 20],'string','+0.1',...
            'callback',{@increment_ac_freq,0.1},'tag','AC FREQ +0.1',...
            'enable','off');
        
        ACFREQ_less01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 70 80 20],'string','-0.1',...
            'callback',{@increment_ac_freq,-0.1},'tag','AC FREQ -0.1',...
            'enable','off');
        
        ACFREQ_less1 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 40 80 20],'string','-1',...
            'callback',{@increment_ac_freq,-1},'tag','AC FREQ -1',...
            'enable','off');
        
        ACFREQ_less10 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[650 10 80 20],'string','-10',...
            'callback',{@increment_ac_freq,-10},'tag','AC FREQ -10',...
            'enable','off');
        
        %% AC AMP
        ACAMPlabel = uicontrol(microscope_window_handle,'style','text',...
            'string','AC AMP',...
            'Position',[750 195 100 20],...
            'tag','ACAMPlabel');
        
        ACAMP = uicontrol(microscope_window_handle,'style','text',...
            'string','??? VP','position',[750 180 100 20],...
            'tag','ACAMP');
        
        ACAMP_plus01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 160 80 20],'string','+0.1',...
            'callback',{@increment_ac_amp,0.1},'tag','AC AMP  +0.1',...
            'enable','off');
        
        ACAMP_plus001 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 135 80 20],'string','+0.01',...
            'callback',{@increment_ac_amp,0.01},'tag','AC AMP  +0.01',...
            'enable','off');

        ACAMP_less001 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 110 80 20],'string','-0.01',...
            'callback',{@increment_ac_amp,-0.01},'tag','AC AMP  -0.01',...
            'enable','off');

        ACAMP_less01 = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 85 80 20],'string','-0.1',...
            'callback',{@increment_ac_amp,-0.1},'tag','AC AMP  -0.1',...
            'enable','off');
        
        mgain_auto = uicontrol('parent',microscope_window_handle,...
            'style','checkbox','string','Auto Gain',...
            'value',0,'position',[10 250 140 20],...
            'callback',@microscope_auto_gain,...
            'tag','mgain_auto');

        % particle injection
        eject_button = uicontrol(microscope_window_handle,'style','pushbutton',...
            'position',[750 30 100 20],...
            'string','eject (AC amp 0)',...
            'callback',@eject_particle,'tag','eject_button',...
            'enable','off');

        eject_length = uicontrol(microscope_window_handle,'style','edit',...
            'string','','position',[750 10 100 20],...
            'tag','eject_length');
        
    end

    function initialize_microscope_variables()
        %create shared data for microscope
        temp.microscope_video_handle = videoinput('pointgrey',1,'Mono8_1280x960');
        temp.microscope_video_handle.FramesPerTrigger = 1;
        triggerconfig(temp.microscope_video_handle, 'manual');
        set(temp.microscope_video_handle, 'TriggerRepeat', Inf);
        temp.src_microscope = getselectedsource(temp.microscope_video_handle);
        temp.src_microscope.GainMode = 'Manual';
        setappdata(main,'microscope_video_handle',temp.microscope_video_handle)
        setappdata(main,'microscope_source_data',temp.src_microscope)
        
    end

    function build_fringe_window(visibility)
        fringe_window_handle = figure('visible','off',...
            'Name','fringe',...
            'Position',[800,100,600,300],...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'fringe_window');
        
        if visibility==1
            set(fringe_window_handle,'visible','on')
        end
        
        %create a button that arms the camera
        farm = uicontrol(fringe_window_handle,'style','togglebutton','String','Run Camera',...
            'Value',0,'position',[10 100 100 20],...
            'Callback',@fringe_camera_arm,...
            'tag','farm');
        
        %create a static text box to show camera status
        fstatus_display = uicontrol(fringe_window_handle,'style','text','string','Camera Status',...
            'position',[120 90 50 30],...
            'tag','fstatus_display');
        set(fstatus_display,'backgroundcolor',[1 1 0]);
        
        %create slider for gain
        fgain_slider = uicontrol(fringe_window_handle,'style','slider',...
            'min',0,'max',18,'value',2,...
            'sliderstep',[0.01 0.2],...
            'position',[10 70 100 20],...
            'Callback',@change_fringe_gain,...
            'tag','fgain_slider');
        
        %create a static text to show camera gain
        fgain_display = uicontrol(fringe_window_handle,'style','text',...
            'string',[num2str(get(fgain_slider,'value'),'%2.1f') ' dB'],...
            'position',[120 70 50 15],...
            'tag','fgain_display');
        
        %create slider for shutter
        fshutter_slider = uicontrol(fringe_window_handle,'style','slider',...
            'min',0.011,'max',33.2,'value',1,...
            'sliderstep',[0.001 0.2],...
            'position',[10 40 100 20],...
            'Callback',@change_fringe_shutter,...
            'tag','fshutter_slider');
        
        %create a static text to show camera shutter
        fshutter_display = uicontrol(fringe_window_handle,'style','text',...
            'string',[num2str(get(fgain_slider,'value')) ' ms'],...
            'position',[120 40 50 15],...
            'Callback',@change_fringe_shutter,...
            'tag','fshutter_display');
        
        ffullscreen_button = uicontrol(fringe_window_handle,'style','pushbutton',...
            'string','Full Screen',...
            'position',[10 10 100 20],...
            'Callback',@fringe_fullscreen,...
            'tag','ffullscreen_button');
        
        
            %create a tab group for voltage plot
        tgroup1 = uitabgroup('parent',fringe_window_handle,...
            'position',[0.3 0.05 0.6 0.9],'tag','tgroup1');
        tg1t1 = uitab('parent',tgroup1,'Title','Fringe Camera',...
            'tag','tg1t1');
        tg1t2 = uitab('parent',tgroup1,'Title','Fringe Data',...
            'tag','tg1t2');
        tg1t3 = uitab('parent',tgroup1,'Title','Latest Andor Spectrum',...
            'tag','tg1t3');
        
              
        %create the axes for the fringe camera
        ax2 = axes('parent',tg1t1,'tag','ax2');
        set(ax2,'xticklabel',[]);
        set(ax2,'xtick',[]);
        set(ax2,'yticklabel',[]);
        set(ax2,'ytick',[]);
        %set the axes to not reset plot propertes
        set(ax2,'nextplot','add');
        set(ax2,'ydir','reverse');
        set(ax2,'xlim',[0 640],'ylim',[0 480])
        
        set(ax2,'Unit','normalized','Position',[0 0 1 1])
       
        %create the axes for the fringe trend display
        ax22 = axes('parent',tg1t2,'tag','ax22');
        set(ax22,'nextplot','replacechildren');
        set(ax22,'xlimmode','auto')
        
        ax23 = axes('parent',tg1t3,'tag','ax23');
        set(ax23,'nextplot','replacechildren');
        set(ax23,'xlimmode','auto')
        
        fopt_checkbox = uicontrol('parent',fringe_window_handle,'style','checkbox',...
            'string','Optimize fringe pattern',...
            'value',0,'position',[10 125, 140, 20],...
            'tag','fopt_checkbox');
        
        fgain_auto = uicontrol('parent',fringe_window_handle,...
            'style','checkbox','string','Auto Gain',...
            'value',0,'position',[10 150 140 20],...
            'callback',@fringe_auto_gain,...
            'tag','fgain_auto');
        
        initialize_fringe_variables();
    end

    function fringe_auto_gain(source,eventdata)
        temp = getappdata(main);
        fgain_control_tags = {'fgain_slider','fgain_display',...
            'fshutter_slider','fshutter_display'};
        if(source.Value)
            % disable gain and shutter sliders and displays
            for tag_name = fgain_control_tags
                handle = find_ui_handle(tag_name{:},fringe_window_handle);
                handle.Enable = 'off';
            end
            % turn on auto shutter and gain
            temp.fringe_source_data.ShutterMode = 'auto';
            temp.fringe_source_data.GainMode = 'auto';
            setappdata(main,'fringe_source_data',temp.fringe_source_data);
        else
            % enable gain and shutter sliders and displays
            for tag_name = fgain_control_tags
                handle = find_ui_handle(tag_name{:},fringe_window_handle);
                handle.Enable = 'on';
            end
            % turn off auto shutter and gain
            temp.fringe_source_data.ShutterMode = 'manual';
            temp.fringe_source_data.GainMode = 'manual';
            setappdata(main,'fringe_source_data',temp.fringe_source_data);
        end
    end

    function initialize_fringe_variables()
        %create shared data for fringe camera
        temp.fringe_video_handle = videoinput('pointgrey',2,'Mono8_1280x960');
        temp.fringe_video_handle.FramesPerTrigger = 1;
        triggerconfig(temp.fringe_video_handle, 'manual');
        set(temp.fringe_video_handle, 'TriggerRepeat', Inf);
        temp.src_fringe = getselectedsource(temp.fringe_video_handle);
        temp.src_fringe.GainMode = 'Manual';
        setappdata(main,'fringe_video_handle',temp.fringe_video_handle)
        setappdata(main,'fringe_source_data',temp.src_fringe)
    end

    function build_arduino_window(visibility)
        arduino_window_handle = figure('visible','off',...
            'Name','Arduino',...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'arduino_window');
        
        if visibility==1
            set(arduino_window_handle,'visible','on')
        end
        
        inject_pushbutton = uicontrol(arduino_window_handle,'style','pushbutton',...
            'String','Inject','position',[250 10 75 20],...
            'callback',@inject,'enable','off',...
            'tag','inject_pushbutton');
        
        burst_pushbutton = uicontrol(arduino_window_handle,'style','pushbutton',...
            'String','Burst','position',[250 35 75 20],...
            'callback',@burst,'enable','off',...
            'tag','burst_pushbutton');
        
        inject_display = uicontrol(arduino_window_handle,'style','text',...
            'string','0','position',[325 10 200 20],...
            'tag','inject_display');
        
        %check which serial ports are available
        serialinfo = instrhwinfo('serial');
        arduino_selectbox = uicontrol(arduino_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 10 100 20],...
            'tag','arduino_selectbox');
        
        arduino_openclose = uicontrol(arduino_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 10 100 20],...
            'callback',@arduinocomms,...
            'tag','arduino_openclose');
        
        bgarduino = uibuttongroup(arduino_window_handle,'Position',[0 0.1 .5 .15],...
            'title','Sensor Select','SelectionChangeFcn',@arduino_mode,...
            'tag','bgarduino');
        
        % Create three radio buttons in the button group.
        arduino_r1 = uicontrol(bgarduino,'Style',...
            'radiobutton',...
            'String','1',...
            'Position',[10 10 30 20],...
            'HandleVisibility','off','enable','on',...
            'tag','arduino_r1');
        
        arduino_r2 = uicontrol(bgarduino,'Style','radiobutton',...
            'String','2',...
            'Position',[50 10 30 20],...
            'HandleVisibility','off','enable','on',...
            'tag','arduino_r2');
        
        ardiuno_r3 = uicontrol(bgarduino,'Style','radiobutton',...
            'String','3',...
            'Position',[90 10 30 20],...
            'HandleVisibility','off','enable','off',...
            'tag','ardiuno_r3');
        
        % temperature plot (lower axis)
        ax20 = axes('parent',arduino_window_handle,...
            'position',[0.15 0.35 0.8 0.25],...
            'tag','ax20');
        set(ax20,'nextplot','replacechildren');
        set(ax20,'xtickmode','auto')
        set(ax20,'xlimmode','auto')
        
        % humidity plot (upper axis)
        ax21 = axes('parent',arduino_window_handle,...
            'position',[0.15 0.7 0.8 0.25],...
            'tag','ax21');
        set(ax21,'nextplot','replacechildren');
        set(ax21,'xtickmode','auto')
        set(ax21,'xlimmode','auto')
        set(ax21,'xtick',[])
        
        linkaxes([ax20 ax21],'x')
    end

    function build_MKS_window(visibility)
        MKS_window_handle = figure('visible','off',...
            'Name','MKS',...
            'Position',[50,100,700,300],...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'mks_window');
        
        if visibility==1
            set(MKS_window_handle,'visible','on')
        end
        
        %check which serial ports are available
        serialinfo = instrhwinfo('serial');
        
        Lauda_T_controlbutton = uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[360 225 100 20],'String','Control ?','callback',@LaudaControl,...
            'enable','off',...
            'tag','Lauda_T_controlbutton');
        
        
        Lauda_chiller_on_off = uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[470 225 100 20],'String','Chiller ?','callback',@LaudaChiller,...
            'enable','off',...
            'tag','Lauda_chiller_on_off');
        
        Julaboselectbox = uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 200 100 20],...
            'tag','Julaboselectbox');
        
        Julaboopenclose = uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 200 100 20],...
            'callback',@Julabocomms,...
            'tag','Julaboopenclose');
        
        Julabo_on_off = uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[230 200 100 20],'String','Pump ?','callback',@JulaboPower,...
            'enable','off',...
            'tag','Julabo_on_off');
        
        Julabo_set_T = uicontrol(MKS_window_handle,'style','edit',...
            'position',[340 200 100 20],'String','T: ?',...
            'callback',@Julabo_send_T,'enable','off',...
            'tag','Julabo_set_T');
        
        Julabo_reported_T = uicontrol(MKS_window_handle,'style','text',...
            'position',[450 200 100 20],'String','T: ?',...
            'tag','Julabo_reported_T');

        mks_selectbox_label = uicontrol(MKS_window_handle,'style','text',...
            'String','MFC controller',...
            'position',[10 265 100 20],...
            'tag','mks_selectbox_label');
        
        MKSselectbox = uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 250 100 20],...
            'tag','MKSselectbox');

        MKSopenclose = uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 250 100 20],...
            'callback',@MKScomms,...
            'tag','MKSopenclose');
        
        Laudaselectbox = uicontrol(MKS_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[240 250 100 20],...
            'tag','Laudaselectbox');
        
        Laudaopenclose = uicontrol(MKS_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[360 250 100 20],...
            'callback',@Laudacomms,...
            'tag','Laudaopenclose');
        
        
        MKScommandpre = uicontrol(MKS_window_handle,'style','text',...
            'string','@253','position',[10 195 50 20],'visible','off',...
            'tag','MKScommandpre');
        
        MKScommandpost = uicontrol(MKS_window_handle,'style','text',...
            'string',';FF','position',[150 195 50 20],'visible','off',...
            'tag','MKScommandpost');
        
        MKScommandline = uicontrol(MKS_window_handle,'style','edit',...
            'position',[50 195 110 20],'visible','off',...
            'tag','MKScommandline');
        
        MKSsendbutton = uicontrol(MKS_window_handle,'style','pushbutton',...
            'position',[210 195 50 20],'string','send',...
            'enable','off','callback',@MKSsend,'visible','off',...
            'tag','MKSsendbutton');
        
        MKSresponse = uicontrol(MKS_window_handle,'style','text',...
            'position',[10 170 250 20],'string','Response:','visible','off',...
            'tag','MKSresponse');
        
        
        bg3 = uibuttongroup(MKS_window_handle,'Position',[0 0.05 .18 .5],...
            'title','Dry CH3','SelectionChangeFcn',@MKS_mode,'tag','bg3');
        
        % Create three radio buttons in the button group.
        mks3_r1 = uicontrol(bg3,'Style',...
            'radiobutton',...
            'String','Open',...
            'Position',[10 80 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks3_r1');
        
        mks3_r2 = uicontrol(bg3,'Style','radiobutton',...
            'String','Close',...
            'Position',[10 60 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks3_r2');
        
        mks3_r3 = uicontrol(bg3,'Style','radiobutton',...
            'String','Setpoint',...
            'Position',[10 40 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks3_r3');
        
        mks3sp = uicontrol(bg3,'style','edit',...
            'position',[10 10 65 20],...
            'callback',{@MKSchangeflow,3,NaN},'enable','off','tag','3');
        
        mks3act = uicontrol(bg3,'style','text',...
            'position',[10 95 65 20],'string','? sccm',...
            'tag','mks3act');

        mks3_plus25 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 115 40 20],'string','+25',...
            'enable','off','tag','mks3_plus25',...
            'callback',{@mks_increment,3,25});

        mks3_plus5 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 93 40 20],'string','+5',...
            'enable','off','tag','mks3_plus5',...
            'callback',{@mks_increment,3,5});

        mks3_plus1 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 69 40 20],'string','+1',...
            'enable','off','tag','mks3_plus1',...
            'callback',{@mks_increment,3,1});

        mks3_minus1 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 46 40 20],'string','-1',...
            'enable','off','tag','mks3_minus1',...
            'callback',{@mks_increment,3,-1});

        mks3_minus5 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 23 40 20],'string','-5',...
            'enable','off','tag','mks3_minus5',...
            'callback',{@mks_increment,3,-5});

        mks3_minus25 = uicontrol(bg3,'style','pushbutton',...
            'position',[80 0 40 20],'string','-25',...
            'enable','off','tag','mks3_minus25',...
            'callback',{@mks_increment,3,-25});

        bg4 = uibuttongroup(MKS_window_handle,'Position',[0.19 0.05 .18 .5],...
            'title','Humid CH4','SelectionChangeFcn',@MKS_mode,'tag','bg4');
        
        % Create three radio buttons in the button group.
        mks4_r1 = uicontrol(bg4,'Style',...
            'radiobutton',...
            'String','Open',...
            'Position',[10 80 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks4_r1');
        
        mks4_r2 = uicontrol(bg4,'Style','radiobutton',...
            'String','Close',...
            'Position',[10 60 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks4_r2');
        
        mks4_r3 = uicontrol(bg4,'Style','radiobutton',...
            'String','Setpoint',...
            'Position',[10 40 65 20],...
            'HandleVisibility','on','enable','on',...
            'tag','mks4_r3');
        
        mks4sp = uicontrol(bg4,'style','edit',...
            'position',[10 10 65 20],...
            'callback',{@MKSchangeflow,4,NaN},'enable','off','tag','4');
        
        mks4act = uicontrol(bg4,'style','text',...
            'position',[10 95 65 20],'string','? sccm',...
            'tag','mks4act');
        
        mks4_plus25 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 115 40 20],'string','+25',...
            'enable','off','tag','mks4_plus25',...
            'callback',{@mks_increment,4,25});

        mks4_plus5 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 93 40 20],'string','+5',...
            'enable','off','tag','mks4_plus5',...
            'callback',{@mks_increment,4,5});

        mks4_plus1 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 69 40 20],'string','+1',...
            'enable','off','tag','mks4_plus1',...
            'callback',{@mks_increment,4,1});

        mks4_minus1 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 46 40 20],'string','-1',...
            'enable','off','tag','mks4_minus1',...
            'callback',{@mks_increment,4,-1});

        mks4_minus5 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 23 40 20],'string','-5',...
            'enable','off','tag','mks4_minus5',...
            'callback',{@mks_increment,4,-5});

        mks4_minus25 = uicontrol(bg4,'style','pushbutton',...
            'position',[80 0 40 20],'string','-25',...
            'enable','off','tag','mks4_minus25',...
            'callback',{@mks_increment,4,-25});

        hum_table = uitable(MKS_window_handle,'Data',[0 -999 -999 -999 -999],'ColumnWidth',{77},...
            'ColumnEditable', [true true true true true],...
            'position',[265 10 425 150],...
            'ColumnName',{'Time (Hr)','Trap (°C)','RH (%)','Total (sccm)','Hookah (°C)'},...
            'celleditcallback',@edit_table,...
            'tag','hum_table');
        
        addrow_button = uicontrol(MKS_window_handle,'style','pushbutton','string','+1 row',...
            'position',[325 170 75 20],...
            'callback',@addrow_fcn,...
            'tag','addrow_button');
        
        simulate_ramp = uicontrol(MKS_window_handle,'style','pushbutton','string','Simulate',...
            'position',[405 170 75 20],...
            'callback',@sim_ramp_fcn,...
            'tag','simulate_ramp');
        
        cleartable_button = uicontrol(MKS_window_handle,'style','pushbutton','string','clear',...
            'position',[485 170 75 20],...
            'callback',@cleartable_fcn,...
            'tag','cleartable_button');
        
        runramp_button = uicontrol(MKS_window_handle,'style','togglebutton','string','Ramp Trap',...
            'position',[565 170 75 20],...
            'callback',@drive_ramps_fcn,...
            'tag','runramp_button');
        
        ramp_text = uicontrol(MKS_window_handle,'style','text','string','Ramp Not Running',...
            'position',[525 200 125 20],...
            'tag','ramp_text');
        
        Lauda_on_off = uicontrol(MKS_window_handle,'style','togglebutton',...
            'position',[470 250 100 20],'String','Pump ?','callback',@LaudaPower,...
            'enable','off',...
            'tag','Lauda_on_off');
        
        Lauda_set_T = uicontrol(MKS_window_handle,'style','edit',...
            'position',[575 250 100 20],'String','T: ?',...
            'callback',@Lauda_send_T,'enable','off',...
            'tag','Lauda_set_T');
        
        Lauda_reported_T = uicontrol(MKS_window_handle,'style','text',...
            'position',[575 220 100 20],'String','T: ?',...
            'tag','Lauda_reported_T');
        
    end

    function build_Andor_window(visibility)
        Andor_window_handle = figure('visible','off',...
            'Name','Andor',...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'andor_window');
        
        if visibility==1
            set(Andor_window_handle,'visible','on')
        end
        
        andor_abort = uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[300 225 100 20],'string','Abort Acquisition',...
            'callback',@andor_abort_sub,...
            'tag','andor_abort');
        
        acoolerinit = uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[10 225 100 20],'string','Connect to Andor',...
            'callback',@andor_initalize,...
            'tag','acoolerinit');
        
        acoolerdisconnect = uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'position',[120 225 100 20],'string','Disconnect Andor',...
            'callback',@andor_disconnect,...
            'tag','acoolerdisconnect');
        
        acooler = uicontrol('parent',Andor_window_handle,'style','togglebutton',...
            'value',0,'position',[10 20 100 20],'string','Cooler OFF',...
            'callback',@andor_chiller_power,...
            'tag','acooler');
        
        acoolerset = uicontrol('parent',Andor_window_handle,'style','edit',...
            'position', [120 20 100 20],'string','-60',...
            'callback',@andor_set_chiller_temp,...
            'tag','acoolerset');
        
        acoolersettext = uicontrol('parent',Andor_window_handle,'style','text',...
            'position', [220 20 50 20],'string','?°C',...
            'tag','acoolersettext');
        
        acooleractualtext = uicontrol('parent',Andor_window_handle,'style','text',...
            'position', [270 20 50 20],'string','?°C',...
            'tag','acooleractualtext');
        
        aaqdata = uicontrol('parent',Andor_window_handle,'style','pushbutton',...
            'string','Get data','position',[10 200 100 20],...
            'callback',@andor_aqdata,'enable','off',...
            'tag','aaqdata');
        
        astatus_selectbox = uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',{'Single Scan','Kinetic Series'},...
            'position',[120 200 100 20],...
            'callback',@change_andor_acquisition,...
            'tag','astatus_selectbox');
        
        aloop_scan = uicontrol(Andor_window_handle,'style','checkbox',...
            'String','Andor Realtime',...
            'position',[250 200 125 20],...
            'callback',@Andor_Realtime,'enable','off',...
            'tag','aloop_scan');
        
        a_integrationtime = uicontrol(Andor_window_handle,'style','edit',...
            'string','15','position',[130 170 100 20],...
            'Callback',@change_andor_exposure_time,...
            'tag','a_integrationtime');
        
        a_integrationtime_lab = uicontrol(Andor_window_handle,'style','text',...
            'string','Integration time:','position',[10 170 120 20],...
            'tag','a_integrationtime_lab');
        
        a_numkinseries = uicontrol(Andor_window_handle,'style','edit',...
            'string','5','position',[130 140 100 20],...
            'Callback',@change_andor_kinetic_length,...
            'tag','a_numkinseries');
        
        a_numkinseries_lab = uicontrol(Andor_window_handle,'style','text',...
            'string','Kinetic series length:','position',[10 140 120 20],...
            'tag','a_numkinseries_lab');
        
        a_kincyctime = uicontrol(Andor_window_handle,'style','edit',...
            'string','30','position',[130 110 100 20],...
            'Callback',@change_andor_kinetic_time,...
            'tag','a_kincyctime');
        
        a_kincyctime_lab = uicontrol(Andor_window_handle,'style','text',...
            'string','Kinetic cycle time:','position',[10 110 120 20],...
            'tag','a_kincyctime_lab');
        
        %%
        a_textreadout = uicontrol(Andor_window_handle,'style','text',...
            'string',{'Andor Communications Display Here'},'max',2,'backgroundcolor',[0.7 0.7 0.7],...
            'position',[275 40 200 150],...
            'tag','a_textreadout');
        
        %make the spectrometer axes
        ax11 = axes('parent',Andor_window_handle,'position',[.1 .55 .8 .4],...
            'tag','ax11');
        set(ax11,'nextplot','replacechildren');
        colormap(ax11,'jet')
        set(ax11,'xlimmode','auto')
        
        %make a button to clear the spectrometer figure
        ax11clear = uicontrol(main,'style','pushbutton','string','cla(ax11)',...
            'position',[600 625 75 20],...
            'callback',{@clearaplot,ax11},...
            'tag','ax11clear');
        
        grating_selectbox = uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',{'Grating 1 600 lines / mm','Grating 2 1200 lines / mm'},...
            'position',[500 200 100 20],...
            'callback',@change_andor_grating,'enable','off',...
            'tag','grating_selectbox');
        
        wavelengths = {'400 nm';'450 nm';...
            '500 nm';'550 nm';...
            '600 nm';'650 nm';...
            '700 nm';'750 nm';...
            '800 nm';'850 nm';...
            '900 nm';'950 nm'};
        
        center_wavelength_selectbox = uicontrol(Andor_window_handle,'style','popupmenu',...
            'String',wavelengths,...
            'position',[500 150 100 20],...
            'callback',@change_andor_wavelength,'enable','off',...
            'tag','center_wavelength_selectbox');
        
    end

    function build_hygrometer_window(visibility)
        
        hygrometer_window_handle = figure('visible','off',...
            'Name','Hygrometer',...
            'MenuBar','none',...
            'ToolBar','none',...
            'tag', 'hygrometer_window');
        
        hygrometer_display = uicontrol(hygrometer_window_handle,'style','text',...
            'position',[250 10 300 20],'string','Hygrometer reading: ?',...
            'tag','hygrometer_display');
        
        if visibility==1
            set(hygrometer_window_handle,'visible','on')
        end
        
        %check which serial ports are available
        serialinfo = instrhwinfo('serial');
        hygrometer_selectbox = uicontrol(hygrometer_window_handle,'style','popupmenu',...
            'String',serialinfo.AvailableSerialPorts,...
            'position',[10 10 100 20],...
            'tag','hygrometer_selectbox');
        
        hygrometer_openclose = uicontrol(hygrometer_window_handle,'style','togglebutton',...
            'String','Port Closed','Value',0,...
            'position',[120 10 100 20],...
            'callback',@hygrometer_comms,'tag','hygrometer');
        
        ax20 = axes('parent',hygrometer_window_handle,...
            'position',[0.15 0.25 0.8 0.7],...
            'tag','ax20');
        set(ax20,'nextplot','replacechildren');
        set(ax20,'xtickmode','auto')
        set(ax20,'xlimmode','auto')
        
        
    end

    function handle = find_ui_handle(tag, parent_handle)
    % FIND_UI_HANDLE  Find handle for UI element by tag and parent.
    %
    %   parent_handle needs to be direct parent (i.e., can't be nested more
    %   deeply). Raise find_ui_handle:lookupFailure exception if not found.
    %
    %   tag can be string or cell array of strings. If cell array, drills
    %   down nested tags, with first element as highest level
    %   (e.g., {'tag1','tag2','tag3'} returns element with tag 'tag3', whose
    %   parent has tag 'tag2', whose parent has tag 'tag1', whose parent has
    %   handle parent_handle.)

        if ischar(tag)
            handle = findobj(parent_handle,'-depth',1,'tag',tag);
            if isempty(handle)
                msgtext = ['Did not find element with tag ', tag,...
                    ' in parent ' parent_handle.Tag];
                ME = MException('find_ui_handle:lookupFailure',msgtext);
                throw(ME);
            end
        elseif iscellstr(tag)
            % drill down through cell array of nested tag strings
            nested_handle = parent_handle;
            for nested_tag = tag
                old_handle = nested_handle;
                nested_handle = findobj(old_handle,'-depth',1,...
                    'tag',nested_tag{:});
                if isempty(nested_handle)
                    msgtext = ['Did not find element with tag ', nested_tag{:},...
                        ' in parent ', old_handle.Tag];
                    ME = MException('find_ui_handle:lookupFailure',msgtext);
                    throw(ME);
                end
            end
            handle = nested_handle;
        else
            msgtext = ['input tag argument needs to be a string or a cell' ...
                 'array of strings'];
            ME = MException('find_ui_handle:badTag', msgtext);
            throw(ME);
        end
    end

%% functions that actually do stuff for main program
    function fasttimer_startstop(source,eventdata)
        if(strcmp(fasttimer.Running,'off'))
            start(fasttimer)
            set(source,'string','Stop background timer')
        else
            stop(fasttimer)
            set(source,'string','Start background timer')
        end
        
    end

    function errortimer_startstop(source,eventdata)
        if(strcmp(errorcatchtimer.Running,'off'))
            start(errorcatchtimer)
            set(source,'string','Stop error catch timer')
        else
            stop(errorcatchtimer)
            set(source,'string','Start error catch timer')
        end
        
    end

    function fasttimerFcn(source,eventdata)
    % FASTTIMERFCN  Run the main loop of the program.
    %
    %   Generally needs to be running for anything to happen, except for
    %   other callback functions triggered directly by button press.
    %
    %   Set up as TimerFcn callback for fasttimer, which executes it
    %   with frequency set by timer's "Period" argument (e.g., 0.1 s).
    %   In turn, fasttimer_startstop() controls fasttimer as
    %   a callback for a "Start/Stop background timer" button press.
    %
    %   (NB other functions, including fasttimerFcn, also stop/start
    %   fasttimer during time-consuming parts of their execution)

        fastloop = tic;
        temp = getappdata(main);
        
        %make default value
        feedbackOK = 0;
        
        %% control how often different parts of fasttimerFcn actually run
        % increment FrameNumber every time function runs (frequency set by
        % Period argument of fasttimer, e.g., 0.1 s).
        % FrameNumber also controls save to file frequency.
        FrameNumber = mod(temp.FrameNumber+1,1000);
        % updatelogic is only related to calling update_cameras()
        updatelogic = mod(FrameNumber,5)==0;
        % NB savelogic is poorly named. Does not control save to file.
        % Instead controls whether certain updated values are written to
        % `main`.
        savelogic = (mod(FrameNumber,100)==0);
        % datalogic controls whether the 'slow' part of the function runs.
        % Save to file can only happen if it's possible for datalogic to be
        % TRUE when FrameNumber==0
        datalogic = (mod(FrameNumber,50)==0);

        %% update fringe and microscope cameras
        try % helps with debugging
            if(~isempty(ishandle(microscope_window_handle))&&~isempty(ishandle(fringe_window_handle)))
                [feedbackOK,fringe_compressed,fringe_image,microscope_image] = update_cameras(source,eventdata,temp,updatelogic,datalogic);
            end
        catch ME
            disp('Problem with update_cameras in fasttimerFcn')
            disp(ME.identifier)
            disp(getReport(ME,'extended'))
            rethrow(ME)
        end
        
        
        %% end of 'fast update' portion
        fasttime = toc(fastloop);
        set(fastupdatetext,'string',['Fast update: ' num2str(fasttime) ' s']);
        setappdata(main,'FrameNumber',FrameNumber)
        
        %% remainder of fasttimerFcn only runs when `datalogic` true
        % reaching end of this code updates 'slow' timestamp
        if(datalogic)
            try % helpful for debugging runtime issues
                stop(fasttimer)
                if(exist('fringe_compressed','var')&&~isempty(fringe_compressed)&&savelogic)
                    % write fringe_compressed fringe pattern to `main`
                    if(~isa(temp.fringe_compressed,'uint8'))
                        temp.fringe_compressed = uint8(temp.fringe_compressed);
                    end
                    temp.fringe_compressed(end+1,:) = uint8(fringe_compressed);
                    temp.fringe_timestamp(end+1) = now;
                    setappdata(main,'fringe_compressed',temp.fringe_compressed);
                    setappdata(main,'fringe_timestamp',temp.fringe_timestamp);
                    % write full images to `main` every 20th time (NB only
                    % happens if fringe_compressed is being created!)
                    if(mod(size(temp.fringe_compressed,1),20)==1)
                        temp.image_timestamp(end+1) = now;
                        setappdata(main,'image_timestamp',temp.image_timestamp);

                        temp.fringe_image(end+1,:,:) = fringe_image;
                        setappdata(main,'fringe_image',temp.fringe_image);

                        % microscope_image will either be empty or image
                        % array. To keep aligned with image_timestamp,
                        % write zeros array to temp.microscope_image if
                        % microscope_image is empty.
                        if(isempty(microscope_image))
                            % hardcode size to match update_cameras()
                            new_micro_image = zeros([480 640],'uint8');
                        else
                            new_micro_image = microscope_image;
                        end
                        temp.microscope_image(end+1,:,:) = new_micro_image;
                        setappdata(main,'microscope_image',...
                            temp.microscope_image);
                    end
                end
                if(isfield(temp,'MKS946_comm'))
                    update_MKS_values(source,eventdata,savelogic);
                end
                if(isfield(temp,'LaudaRS232'))
                    update_Lauda(savelogic);
                end
                if(isfield(temp,'JulaboRS232'))
                    update_Julabo(savelogic);
                end
                if(isfield(temp,'arduino_comm')&&savelogic)
                    update_rh_t();
                end
                if(isfield(temp,'Hygrometer_comms')&&datalogic)
                    update_hygrometer_data()
                    % if hot for >10 minutes, send back to regular mode
                    if(temp.hygrometer_data(find(temp.hygrometer_data(:,1)>(now-15/60/24),1,'first'),2)>90)
                       force_hygrometer_normal()
                    end
                end
                if(temp.AndorFlag)
                    update_Andor_values();
                    get_andor_data(source,eventdata);
                end
                % record and plot DC feedback voltage data
                if(feedbackOK)
                    temp = getappdata(main);

                    % write DC voltage data to array of feedback or no feedback
                    % values
                    voltage_dc_trap = getappdata(main,'voltage_dc_trap');
                    mhold_position = find_ui_handle('mhold_position',...
                        microscope_window_handle);
                    if(voltage_dc_trap>=0&mhold_position.Value)
                        temp.VoltageData(end+1,:) = [now voltage_dc_trap];
                        setappdata(main,'VoltageData',temp.VoltageData)
                    else
                        temp.voltage_data_nofeedback(end+1,:) = [now voltage_dc_trap];
                        setappdata(main,'voltage_data_nofeedback',...
                            temp.voltage_data_nofeedback);
                    end

                    % plot DC voltage data if feedback voltage data exists,
                    % with different markers for feedback and nofeedback
                    tgroup1 = find_ui_handle('tgroup1',...
                        microscope_window_handle);
                    vplot_tab = find_ui_handle('tg1t2',tgroup1);
                    vplot_selected = (tgroup1.SelectedTab == vplot_tab);
                    vplot_ax = find_ui_handle('ax20',vplot_tab);
                    if(size(temp.VoltageData,1)>1&&vplot_selected)
                        cla(vplot_ax);
                        vplot_ax.XLimMode = 'Auto';
                        vplot_ax.XTickMode = 'Auto';
                        vplot_ax.XTickLabelMode = 'Auto';
                        plot(vplot_ax,temp.VoltageData(:,1),...
                            temp.VoltageData(:,2).*1000,'.');
                        if(size(temp.voltage_data_nofeedback,1)>1)
                           hold(vplot_ax,'on');
                           plot(vplot_ax,temp.voltage_data_nofeedback(:,1),temp.voltage_data_nofeedback(:,2).*1000,'o')
                        end
                        ylabel(vplot_ax,'V DC (V)')
                        datetick(vplot_ax,'x','(DD).HH','keepticks')
                        xlabel(vplot_ax,'Time (DD).HH')
                    else
                        cla(vplot_ax);
                    end
                end

                % update Andor spectrum (plotted both Andor window and
                % third tab of fringe window)
                fringe_andor_plot = find_ui_handle({'tgroup1','tg1t3','ax23'},...
                    fringe_window_handle);
                set(fringe_andor_plot,'ydir','normal');
                update_andor_plot_1D(fringe_andor_plot);
                % andor window plot depends on whether plotting single scan or
                % kinetic series
                astatus_selectbox = find_ui_handle('astatus_selectbox',...
                    Andor_window_handle);
                if(temp.AndorFlag&&astatus_selectbox.Value==1)
                    ax11 = find_ui_handle('ax11',Andor_window_handle);
                    update_andor_plot_1D(ax11);
                elseif(temp.AndorFlag&&astatus_selectbox.Value==2)
                    update_andor_plot_2D();
                end

                if(temp.RampFlag)
                    dt = (now-temp.RampTime_init)*24;
                    runramp_button = find_ui_handle('runramp_button',...
                        MKS_window_handle);
                    hum_table = find_ui_handle('hum_table',MKS_window_handle);
                    ramp_text = find_ui_handle('ramp_text',MKS_window_handle);
                    mks3sp = find_ui_handle({'bg3','3'},MKS_window_handle);
                    mks4sp = find_ui_handle({'bg4','4'},MKS_window_handle);
                    if(dt>temp.Ramp_data(end,1))
                        %the ramp is over
                        runramp_button.Value = 0;
                        set(hum_table,'enable','on')
                        setappdata(main,'RampFlag',0)
                        set(runramp_button,'string','Ramp Trap')
                    else
                        ramp_text.String = ['Ramp: ' num2str(dt,'%2.1f') ' of ' num2str(temp.Ramp_data(end,1),'%2.1f') ' hrs'];
                        flow1 = min([interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,2),dt,'linear') 200]);
                        flow2 = min([interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,3),dt,'linear') 200]);
                        T = interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,4),dt,'linear');
                        JulaboT = interp1(temp.Ramp_data(:,1),temp.Ramp_data(:,5),dt,'linear');
                        %ensure flow controllers are turned on if flow ~= 0
                        if(flow1>=4) %dry
                            %make sure MFC is turned to SETPOINT
                            MKSsend(source,eventdata,'QMD3!SETPOINT');
                            MKSchangeflow(source,eventdata,3,flow1);
                            mks3sp.String = flow1;
                        elseif(flow1<4)
                            %turn MFC to CLOSE
                            MKSsend(source,eventdata,'QMD3!CLOSE');
                            mks3sp.String = 'CLOSED';
                        end
                        if(flow2>=4) %humid
                            %make sure MFC is turned to SETPOINT
                            MKSsend(source,eventdata,'QMD4!SETPOINT');
                            MKSchangeflow(source,eventdata,4,flow2);
                            mks4sp.String = flow2;
                        elseif(flow2<4)
                            %turn MFC to CLOSE
                            MKSsend(source,eventdata,'QMD4!CLOSE');
                            mks4sp.String = 'CLOSED';
                        end

                        Lauda_send_T(source,eventdata,T);
                        update_Lauda(savelogic);
                        Julabo_send_T(source,eventdata,JulaboT);
                        update_Julabo(savelogic);
                    end
                end

                % update fringe data tab plot, if selected tab in tab group and
                % fringe data exists
                ftgroup = find_ui_handle('tgroup1',fringe_window_handle);
                fdata_tab = find_ui_handle('tg1t2',ftgroup);
                fdata_selected = (ftgroup.SelectedTab == fdata_tab);
                if(size(temp.fringe_compressed,1)>1&fdata_selected)
                    peaksep = ACBAR_realtime_fringe_analysis(temp);

                    fdata_ax = find_ui_handle('ax22',fdata_tab);
                    cla(fdata_ax);
                    errorbar(fdata_ax,...
                        temp.fringe_timestamp,peaksep(:,1),peaksep(:,2));
                    fdata_ax.XLimMode = 'auto';
                    fdata_ax.XTickMode = 'auto';
                    datetick(fdata_ax,'x','DD.HH')
                    xlabel(fdata_ax,'Time (DD.HH)')
                    ylabel(fdata_ax,'Peak Separation (px)')
                end

                set(slowupdatetext,'string',['Slow: ' datestr(now)])

                % save contents of `temp` to file every time datalogic is
                % true and FrameNumber rolls over to 0 (independent of
                % savelogic), using v7.3 .mat format.
                if(save_checkbox.Value&FrameNumber==0)
                    % define absolute save file path in acbar_data folder
                    save_path = ['C:\Users\Huisman\Documents\acbar_data\' ...
                        save_filename.String];
                    save(save_path,'temp','-v7.3')
                end
                start(fasttimer)
            catch ME
                % in past, exception has been MATLAB:subsassigndimmismatch
                % from appending new microscope_image with size mismatch
                % compared to temp.microscope_image (due to camera being
                % started/stopped)
                disp(ME.identifier)
                disp(getReport(ME,'extended'))
                rethrow(ME)
            end
        end
        
    end

    function [peaksep] = ACBAR_realtime_fringe_analysis(temp)
        %try putting plots in time order like the LED spectra are
        X = temp.fringe_timestamp;
        nday = mean(diff(X)); %use the average spacing
        newX = X(1):nday:X(size(temp.fringe_compressed,1));
        newX_coordinates = interp1(X,1:size(X,2),newX);
        new_1Dfringe = temp.fringe_compressed(round(newX_coordinates),:);

        dX = diff(newX_coordinates);
        %find identical data
        gaps = find(dX<0.999);

        for i = 2:length(gaps)
            if(gaps(i)==(gaps(i-1)+1)) %if gaps are sequential
                new_1Dfringe(gaps(i),:) = NaN;
            end
        end

        %convert new_1Dfringe to double to matlab work on it
        new_1Dfringe = double(new_1Dfringe);
        %allow for plotting if desired
        if(0)
            im1 = image(new_1Dfringe');
            ax1 = gca;
            set(im1,'cdatamapping','scaled')
            set(im1,'XData',[newX(1) newX(end)])
            set(ax1,'XLim',[newX(1) newX(end)])

            onedpcts = prctile(new_1Dfringe,[10 90]);
            lowerlimit = min(onedpcts(1,onedpcts(1,:)~=0));
            upperlimit = max(onedpcts(2,onedpcts(1,:)~=0));
            %upperlimit = 1500;
            caxis([lowerlimit upperlimit])
            ylabel('Pixel Number');
            xlabel('Time (DD HH)')
            datetick('x','DD HH')
        end

        %preallocate for 30 peaks at most
        peakheights = zeros(size(new_1Dfringe,1),30);
        peaklocs = zeros(size(new_1Dfringe,1),30);
        offset = 15;
        diffpeaklocs = [];
        h = waitbar(0,['Fringe peak analysis...']);
        for i = 1:size(new_1Dfringe,1)
            [p,l] = findpeaks(smooth(new_1Dfringe(i,offset:end-offset)),...
                'MinPeakDistance',10);
            peakheights(i,1:length(p)) = p;
            peaklocs(i,1:length(l)) = l;
            % pause
            diffpeaklocs = diff(peaklocs);
            if(mod(i,10)==0)
                waitbar(i/size(new_1Dfringe,1),h)
            end
        end
        close(h)

        %find the average and std of difference in peak location, up to the
        %negative one that indicates it is not a peak
        diffpeaklocs = diff(peaklocs,1,2);
        for i = 1:size(diffpeaklocs,1)
            maxinx = find(diffpeaklocs(i,:)>0,1,'last');
            peaksep(i,:) = [mean(diffpeaklocs(i,1:maxinx)) std(diffpeaklocs(i,1:maxinx))];
        end

        clear ax1 h i im1 l lowerlimit maxinx n nday p upperlimit diffpeaklocs
    end
        



    function errorcatchFcn(source,eventdata)
        wasrunning = strcmp(get(fasttimer,'running'),'on');
        if(wasrunning)
            stop(fasttimer)
            pause(0.25)
        end
        %check to see if the timer button is pushed, but timer not running
        if(~wasrunning&&get(fasttimer_button,'value'))
            disp(['Auto restart fast timer at ' datestr(now)])
            beep;
            start(fasttimer)
        elseif(wasrunning&&get(fasttimer_button,'value'))
            %everything is fine, restart the timer
            disp('Everything is fine with the error catch timer')
            start(fasttimer)
        end
    end

    function toggle_window_visibility(source,eventdata,tag_name)
    % TOGGLE_WINDOW_VISIBILITY  Toggle visibility of window with tag_name.
    %
    %   Searches only direct children of graphics root, which should be
    %   figure windows.

        selected_window_handle = find_ui_handle(tag_name,groot);
        if(get(source,'value'))
            set(selected_window_handle,'visible','on')
        else
            set(selected_window_handle,'visible','off')
        end
    end

    function SCRAM_COMMS(source,eventdata)
    % SCRAM_COMMS  Delete all serial connections and refresh connection list.

        delete(instrfindall)
        serialinfo = instrhwinfo('serial');

        % refresh in microscope window
        srs1openclose = find_ui_handle('SRS1openclose',...
            microscope_window_handle);
        srs2openclose = find_ui_handle('SRS2openclose',...
            microscope_window_handle);
        srs1selectbox = find_ui_handle('SRS1selectbox',...
            microscope_window_handle);
        srs2selectbox = find_ui_handle('SRS2selectbox',...
            microscope_window_handle);
        set(srs1selectbox,'String',serialinfo.AvailableSerialPorts);
        set(srs1openclose,'value',0,'string','Port Closed')
        set(srs2selectbox,'String',serialinfo.AvailableSerialPorts);
        set(srs2openclose,'value',0,'string','Port Closed')

        % refresh in arduino window
        if(ishandle(arduino_window_handle))
            arduino_selectbox = find_ui_handle('arduino_selectbox',...
                arduino_window_handle);
            set(arduino_selectbox,'String',serialinfo.AvailableSerialPorts);
            arduino_openclose = find_ui_handle('arduino_openclose',...
                arduino_window_handle);
            set(arduino_openclose,'value',0,'string','Port Closed')
        end

        % refresh in MKS window
        if(ishandle(MKS_window_handle))
            julaboselectbox = find_ui_handle('Julaboselectbox',...
                MKS_window_handle);
            mksselectbox = find_ui_handle('MKSselectbox',...
                MKS_window_handle);
            laudaselectbox = find_ui_handle('Laudaselectbox',...
                MKS_window_handle);
            julaboopenclose = find_ui_handle('Julaboopenclose',...
                MKS_window_handle);
            mksopenclose = find_ui_handle('MKSopenclose ',...
                MKS_window_handle);
            laudaopenclose = find_ui_handle('Laudaopenclose',...
                MKS_window_handle);
            set(julaboselectbox,'String',serialinfo.AvailableSerialPorts)
            set(mksselectbox,'String',serialinfo.AvailableSerialPorts)
            set(laudaselectbox,'String',serialinfo.AvailableSerialPorts)
            set(julaboopenclose,'value',0,'string','Port Closed')
            set(mksopenclose,'value',0,'string','Port Closed')
            set(laudaopenclose,'value',0,'string','Port Closed')
        end
    end

    function flush_data(source,eventdata)
    % FLUSH_DATA  Clear data from program memory.
    %
    %   Before clearing data, first provide a confirmation dialog and then
    %   save data to file a final time. Do not clear data from list of
    %   `namestokeep`, which are used in an ongoing way for program
    %   operation.

        stop(fasttimer)
        temp = getappdata(main);
        choice = questdlg('This will clear all data in program memory. Are you sure?', ...
            'Yes','No');
        if(strcmp(choice,'Yes'))
            if(save_checkbox.Value)
                % define absolute save file path in acbar_data folder
                save_path = ['C:\Users\Huisman\Documents\acbar_data\' ...
                    save_filename.String];
                save(save_path,'temp','-v7.3')
            end
            % turn off save checkbox and reset filename
            set(save_checkbox,'value',0);
            set(save_filename,'string','Enter new file name');

            listofnames = fieldnames(temp);
            namestokeep = {'microscope_video_handle';
                'microscope_source_data';'fringe_video_handle';...
                'fringe_source_data';'IdealY';'RampFlag';'AndorCalPoly';...
                'AndorFlag';'UPSInumber';'camera1Flag';'camera2Flag';...
                'FrameNumber';'UPSInumber';'ShamrockGrating';...
                'ShamrockXCal';'MKS946_comm';'LaudaRS232';...
                'DS345_AC';'arduino_comm';'JulaboRS232';...
                'Hygrometer_comms';'voltage_dc_trap';'amp_ac_trap';...
                'freq_ac_trap';'PID_oldvalue';'PID_timestamp';'PID_Iterm'};
            for i = 1:length(listofnames)
                if(~ismember(listofnames{i},namestokeep))
                    setappdata(main,listofnames{i},[])
                end
            end
        end

        start(fasttimer)
    end

%% functions that actually do stuff for all subprograms
    function wait_a_second(handlein)
        set(handlein ,'pointer','watch')
    end

    function good_to_go(handlein)
        set(handlein,'pointer','arrow')
    end

    function clearaplot(source,eventdata,plotpointer)
        cla(plotpointer);
    end

    function [feedbackOK,fringe_compressed,fringe_image,microscope_image] = update_cameras(source,eventdata,temp,updatelogic,datalogic)
    % UPDATE_CAMERAS  Get raw and processed data from cameras if turned on.
    %
    %   In addition to returned values, updates ycentroid of "blob"
    %   detected in microscope image.
    %
    %   Returns:
    %   --------
    %   feedbackOK : boolean
    %   Whether DC feedback is ok. Handled by microscope_blob_annotation().
    %
    %   fringe_compressed : 1x480 uint8 array or empty
    %   Horizontal fringes computed by fringe_annotation().
    %
    %   fringe_image : 480x640 uint8 array or empty
    %   Full image from fringe camera (reduced from 960x1280). Only
    %   nonempty when fringe annotation is turned on.
    %
    %   microscope_image : 480x640 uint8 array or empty
    %   Full image from microscope camera (reduced from 960x1280).

        feedbackOK = 0;
        fringe_compressed = [];
        fringe_image = [];
        microscope_image = [];
        %get video data if running
        camera1running = isrunning(temp.microscope_video_handle);
        camera2running = isrunning(temp.fringe_video_handle);
        % logic based on which cameras are running
        % NB each option only happens once every `updatelogic` loops *except*
        % for the first case, where only the microscope camera is running. This
        % has the effect of making the 'fast update' time slower in this case,
        % since the microscope camera is updating more often.
        if(camera1running&&~camera2running)
            % get image from microscope camera and resize to 480x640
            trigger(temp.microscope_video_handle);
            IM1 = getdata(temp.microscope_video_handle,1,'uint8');
            IM1_small = imresize(IM1,[480 640]);
            % look for droplet blob
            [~,ycentroid,feedbackOK] = microscope_blob_annotation(IM1_small,updatelogic);
            % check if microscope hold button is depressed
            hold_button_handle = find_ui_handle('mhold_position',...
                microscope_window_handle);
            hold_button_depressed = get(hold_button_handle,'value');
            % run microscope_feedback_hold, if appropriate
            if(hold_button_depressed&&feedbackOK&&datalogic)
                % need existing y-position of blob for feedback. Write for
                % next time through loop if doesn't already exist.
                if(isfield(temp,'PID_oldvalue'))
                    microscope_feedback_hold(source,eventdata,ycentroid);
                else
                    setappdata(main,'PID_oldvalue',ycentroid);
                end
            end
            microscope_image = uint8(IM1_small);
        elseif(camera2running&&updatelogic&&~camera1running)
            % get image from fringe camera and resize to 480x640
            trigger(temp.fringe_video_handle);
            IM2 = getdata(temp.fringe_video_handle,1,'uint8');
            IM2_small = imresize(IM2,[480 640]);
            % update Fringe Camera tab image in fringe window
            fcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax2'},...
                fringe_window_handle);
            cla(fcamera_ax)
            imshow(IM2_small,'parent',fcamera_ax)
            str = ['Time: ' datestr(now)];
            xtextloc = 225;
            ytextloc = 450;
            text(fcamera_ax,double(xtextloc),double(ytextloc),str,...
                'color','white')
            % do fringe annotation if turned on
            fringe_button_handle = find_ui_handle('fopt_checkbox',...
                fringe_window_handle);
            fringe_button_depressed = get(fringe_button_handle,'value');
            if(fringe_button_depressed)
                [fringe_compressed] = fringe_annotation(IM2_small);
                fringe_image = uint8(IM2_small);
            end
        elseif(camera1running&&camera2running&&updatelogic)
            % get images from microscope and fringe cameras, resize each
            % to 480x640
            trigger(temp.microscope_video_handle);
            trigger(temp.fringe_video_handle);
            IM1 = getdata(temp.microscope_video_handle,1,'uint8');
            IM2 = getdata(temp.fringe_video_handle,1,'uint8');
            IM1_small = imresize(IM1,[480 640]);
            IM2_small = imresize(IM2,[480 640]);

            % look for droplet blob
            [~,ycentroid,feedbackOK] = microscope_blob_annotation(IM1_small,updatelogic);
            % check if microscope hold button is depressed
            hold_button_handle = find_ui_handle('mhold_position',...
                microscope_window_handle);
            hold_button_depressed = get(hold_button_handle,'value');
            % run microscope_feedback_hold, if appropriate
            if(hold_button_depressed&&feedbackOK&&datalogic)
                % need existing y-position of blob for feedback. Write for
                % next time through loop if doesn't already exist.
                if(isfield(temp,'PID_oldvalue'))
                    microscope_feedback_hold(source,eventdata,ycentroid);
                else
                    setappdata(main,'PID_oldvalue',ycentroid);
                end
            end
            microscope_image = uint8(IM1_small);

            % update Fringe Camera tab image in fringe window
            fcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax2'},...
                fringe_window_handle);
            cla(fcamera_ax)
            imshow(IM2_small,'parent',fcamera_ax)
            str = ['Time: ' datestr(now)];
            xtextloc = 225;
            ytextloc = 450;
            text(fcamera_ax,double(xtextloc),double(ytextloc),str,...
                'color','white')
            % do fringe annotation if turned on
            fringe_button_handle = find_ui_handle('fopt_checkbox',...
                fringe_window_handle);
            fringe_button_depressed = get(fringe_button_handle,'value');
            if(fringe_button_depressed)
                [fringe_compressed] = fringe_annotation(IM2_small);
                fringe_image = uint8(IM2_small);
            end
        end

        %get logical flag for camera1 status
        if(~camera1running&&temp.camera1Flag)
            %start the camera feed
            start(temp.microscope_video_handle);
        elseif(camera1running&&~temp.camera1Flag)
            %stop the camera feed
            stop(temp.microscope_video_handle);
        end

        %get logical flag for camera2 status
        if(~camera2running&&temp.camera2Flag)
            %start the camera feed
            start(temp.fringe_video_handle);
        elseif(camera2running&&~temp.camera2Flag)
            %stop the camera feed
            stop(temp.fringe_video_handle);
        end
    end

%% functions that actually do stuff for microscope camera
    function microscope_fullscreen(source,eventdata)
        temp = getappdata(main);
        preview(temp.microscope_video_handle)
        set(source,'value',0)
    end

    function microscope_auto_gain(source,eventdata)
        temp = getappdata(main);
        mgain_control_tags = {'mgain_slider','mgain_display',...
            'mshutter_slider','mshutter_display'};
        if(source.Value)
            % disable gain and shutter sliders and displays
            for tag_name = mgain_control_tags
                handle = find_ui_handle(tag_name{:},microscope_window_handle);
                handle.Enable = 'off';
            end
            % turn on auto shutter and gain
            temp.microscope_source_data.ShutterMode = 'auto';
            temp.microscope_source_data.GainMode = 'auto';
            setappdata(main,'microscope_source_data',temp.microscope_source_data);
        else
            % enable gain and shutter sliders and displays
            for tag_name = mgain_control_tags
                handle = find_ui_handle(tag_name{:},microscope_window_handle);
                handle.Enable = 'on';
            end
            % turn off auto shutter and gain
            temp.microscope_source_data.ShutterMode = 'manual';
            temp.microscope_source_data.GainMode = 'manual';
            setappdata(main,'microscope_source_data',temp.microscope_source_data);
        end
    end

    function microscope_camera_arm(source,eventdata)
    % MICROSCOPE_CAMERA_ARM  Toggle arm state of fringe camera.
    %
    %   Toggles camera1Flag global state and appropriate UI camera controls.

        temp = getappdata(main);
        mgain_auto = find_ui_handle('mgain_auto',microscope_window_handle);
        mstatus_display = find_ui_handle('mstatus_display',...
            microscope_window_handle);
        mfullscreen_button = find_ui_handle('mfullscreen_button',...
            microscope_window_handle);
        mgain_slider = find_ui_handle('mgain_slider',microscope_window_handle);
        mshutter_slider = find_ui_handle('mshutter_slider',...
            microscope_window_handle);
        midealy_get = find_ui_handle('midealy_get',microscope_window_handle);
        mhold_position = find_ui_handle('mhold_position',...
            microscope_window_handle);

        if(get(source,'value'))
            % turn camera flag on
            setappdata(main,'camera1Flag',1)
            % toggle ui controls
            mgain_auto.Enable = 'off';
            set(mstatus_display,'string','Camera Armed');
            set(mstatus_display,'backgroundcolor',[0.5 1 0.5]);
            set(mfullscreen_button,'visible','off')
            set(mgain_slider,'visible','off')
            set(mshutter_slider,'visible','off')
            set(midealy_get,'enable','on')
        else
            % turn camera flag off
            setappdata(main,'camera1Flag',0)
            % toggle ui controls
            set(mstatus_display,'string','Camera Ready');
            set(mstatus_display,'backgroundcolor',[1 0.5 0.5]);
            mgain_auto.Enable = 'on';
            set(mfullscreen_button,'visible','on')
            set(mgain_slider,'visible','on')
            set(mshutter_slider,'visible','on')
            set(midealy_get,'enable','off')
            % stop holding
            if(get(mhold_position,'value'))
                set(mhold_position,'string','Stopped Holding')
                set(mhold_position,'value',0)
            end
        end
    end

    function change_microscope_gain(source,eventdata)
    % CHANGE_MICROSCOPE_GAIN  Change microscope camera gain based on slider.
    %
    %   Write value to camera, update display string, and update image.

        temp = getappdata(main);
        new_gain = source.Value;
        % write value to camera
        temp.microscope_source_data.Gain = new_gain;
        % update display string
        mgain_display = find_ui_handle('mgain_display',...
            microscope_window_handle);
        new_gain_str = [num2str(new_gain,'%10.1f') ' dB'];
        set(mgain_display,'string',new_gain_str)
        % write source data back to application data
        setappdata(main,'microscope_source_data',temp.microscope_source_data);
        % update image
        wait_a_second(microscope_window_handle);
        frame = getsnapshot(temp.microscope_video_handle);
        frame_small = imresize(frame,[480 640]);
        good_to_go(microscope_window_handle);
        mcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax1'},...
            microscope_window_handle);
        imshow(frame_small,'parent',mcamera_ax);
    end

    function change_microscope_shutter(source,eventdata)
    % CHANGE_MICROSCOPE_SHUTTER  Change microscope shutter speed from slider.
    %
    %   Write value to camera, update display string, and update image.

        temp = getappdata(main);
        newshutter = source.Value;
        % write value to camera
        temp.microscope_source_data.Shutter = newshutter;
        % update display string
        mshutter_display = find_ui_handle('mshutter_display',...
            microscope_window_handle);
        new_shutter_str = [num2str(newshutter,'%10.1f') ' ms'];
        set(mshutter_display,'string',new_shutter_str)
        % write source data back to application data
        setappdata(main,'microscope_source_data',temp.microscope_source_data);
        % update image
        wait_a_second(microscope_window_handle);
        frame = getsnapshot(temp.microscope_video_handle);
        frame_small = imresize(frame,[480 640]);
        good_to_go(microscope_window_handle);
        mcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax1'},...
            microscope_window_handle);
        imshow(frame_small,'parent',mcamera_ax);
    end

    function getidealy(source,eventdata)
    % GETIDEALY  Set ideal y-axis position of droplet to current y-centroid.

        stop(fasttimer)

        pause(0.25)
        temp = getappdata(main);
        % collect new image
        trigger(temp.microscope_video_handle);
        IM1 = getdata(temp.microscope_video_handle);
        IM1_small = imresize(IM1,[480 640]);
        % find current droplet y-axis position (centroid)
        [~,idealy] = microscope_blob_annotation(IM1_small,0);
        % update display and main.IdealY value
        midealy = find_ui_handle('midealy',microscope_window_handle);
        set(midealy,'string',num2str(idealy));
        setappdata(main,'IdealY',idealy);

        start(fasttimer)
    end

    function [x_centroid,y_centroid,feedbackOK] = microscope_blob_annotation(imdata,plotflag)
    % MICROSCOPE_BLOB_ANNOTATION  Locate droplet blob location and maybe plot.
    %
    %   imdata is image from microscope camera.
    %
    %   If plotflag is 1, redraw microscope image along with any bounding boxes
    %   of detected blobs (red) and a box surrounding the overall centroid
    %   (green).
    %
    %   x_centroid and y_centroid are overall centroid of one or two largest
    %   detected blobs.
    %
    %   feedbackOK is 1 or 0 depending on whether any blobs were detected or
    %   not (i.e., can't do DC feedback if camera doesn't see blob).

        feedbackOK = 1;
        mcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax1'},...
            microscope_window_handle);

        % calculate Area, Centroid, and BoundingBox of each detected region in
        % binarized (i.e., black or white) version of imdata; sort by area
        stats = regionprops(im2bw(imdata,0.3));
        sortedstats = sort([stats.Area]);

        % logic based on number of detected regions, including define index of
        % box(es) of interest
        if(length(sortedstats)==1)
            box_ind = find([stats.Area]==sortedstats(end));
        % if no blobs detected, turn off dc feedback, redraw microscope
        % image (with no annotation squares), and return [-999 -999 0].
        elseif(isempty(sortedstats))
            x_centroid = -999;
            y_centroid = -999;
            feedbackOK = 0;
            mhold_position = find_ui_handle('mhold_position',...
                microscope_window_handle);
            if(get(mhold_position,'value'))
                set(mhold_position,'string','Stopped Holding')
                % stop the ramp, if feedback was active. note it should be
                % possible to run a ramp with no feedback, but turning
                % feedback on and having it turn itself off will stop ramp.
                temp = getappdata(main);
                if(temp.RampFlag)
                    hum_table = find_ui_handle('hum_table',MKS_window_handle);
                    ramp_text = find_ui_handle('ramp_text',MKS_window_handle);
                    runramp_button = find_ui_handle('runramp_button',...
                        MKS_window_handle);
                    set(hum_table,'enable','on')
                    setappdata(main,'RampFlag',0)
                    set(runramp_button,'string','Ramp Trap')
                    set(ramp_text,'string','Stopped Ramp')
                    % this used to refer to index of ramp_text ... bug?
                    set(runramp_button,'value',0)
                    % delete table entries that have already passed
                    data = hum_table.Data;
                    data_times = hum_table.Data(:,1);
                    now_data_time = (now-temp.RampTime_init)*24;
                    end_prev_data = find(data_times<now_data_time,1,'last');
                    data(2:end_prev_data,:) = [];
                    % adjust timestamps to match
                    data(2:end,1) = data(2:end,1)-now_data_time;
                    hum_table.Data = data;
                end
            end
            set(mhold_position,'value',0)
            if(plotflag)
                set(microscope_window_handle,'CurrentAxes',mcamera_ax);
                cla(mcamera_ax)
                imshow(imdata,'parent',mcamera_ax);
                str = ['Time: ' datestr(now)];
                xtextloc = 225;
                ytextloc = 450;
                text(mcamera_ax,double(xtextloc),double(ytextloc),str,...
                    'color','white')
            end
            return
        % if second-largest box is signifcant fraction of largest, use two
        % largest boxes (often get two images of one droplet)
        elseif((sortedstats(end-1)/sortedstats(end))>0.3)
            box_ind = find([stats.Area]>=sortedstats(end-1));
        % otherwise, only one meaningful box
        else
            box_ind = find([stats.Area]==sortedstats(end));
        end
        
        % calculate overall centroid from box(es). If multiple boxes, overall
        % "centroid" taken as mean of individual centroids.
        centroid_data = [stats(box_ind).Centroid];
        y_centroid = mean(centroid_data(2:2:end));
        x_centroid = mean(centroid_data(1:2:end));

        % redraw microscope image with red rectangles annotating detected boxes
        % and green box (fixed size 40x40) surrounding overall centroid
        if(plotflag)
            set(microscope_window_handle,'currentaxes',mcamera_ax)
            cla(mcamera_ax)
            imshow(imdata,'parent',mcamera_ax)
            str = ['Time: ' datestr(now)];
            xtextloc = 225;
            ytextloc = 450;
            text(mcamera_ax,double(xtextloc),double(ytextloc),str,...
                'color','white')
            for i = 1:length(box_ind)
                rectangle('parent',mcamera_ax,...
                    'Position',stats(box_ind(i)).BoundingBox,...
                    'EdgeColor','r', 'LineWidth', 1);
            end
            set(microscope_window_handle,'currentaxes',mcamera_ax)
            rectangle('parent',mcamera_ax,...
                'Position',[x_centroid-20 y_centroid-20 40 40],...
                'Edgecolor','g','LineWidth',1)
        end
    end

    function mholdposition(source,eventdata)
    % MHOLDPOSITION  Start or stop DC feedback, from button press.

        stop(fasttimer)

        % voltage_dc_trap is -1 if Arduino comms haven't been initialized
        % with DAC connection.
        if(getappdata(main,'voltage_dc_trap')<0)
            % missing DC control, turn button back off
            set(source,'string','DC cxn req''d')
            set(source,'value',0)
            start(fasttimer)
            return
        end

        if(get(source,'value'))
            % toggle on
            set(source,'string','Holding...')
            currenttime = clock;
            % initialize global vars related to PID
            setappdata(main,'PID_timestamp',currenttime)
            setappdata(main,'PID_Iterm',0);
        else
            % toggle off
            set(source,'string','Hold Position')
        end

        start(fasttimer)
    end

    function microscope_feedback_hold(source,eventdata,ycentroid)
    % MICROSCOPE_FEEDBACK_HOLD  Use PID control to adjust trap voltages.
    %
    %   Set DC voltage using PID algorithm with 3 hard-coded tuning
    %   parameters. Also proportionally update the AC frequency (in an
    %   attempt to prevent hitting the spring point?), if checked.
    %
    %   Parameter ycentroid is measured vertical pixel position.
    %
    %   Side effects include:
    %   - set PID_timestamp, PID_Iterm, and PID_oldvalue appdata in main
    %   - call set_dc()
    %   - call set_ac_freq() (if box checked)
    %   - update AC frequency display window text

        temp = getappdata(main);
        currenttime = clock;

        % Three PID tuning parameters. Roughly speaking,
        % (1) proportional gain kp decreases rise time, increases
        % overshoot, decreases steady-state error
        % (2) integral gain ki decreases rise time, increases overshoot,
        % increases settling time, decreases steady-state error
        % (3) differential gain kd decreases overshoot, decreases settling
        % time (but can also amplify noise)
        kp = 1e-1;
        ki = 1e-6;
        kd = 1e-2;
        % tracking error
        error = (ycentroid-temp.IdealY);

        %  elapsed time since last function call, in seconds
        dt = etime(currenttime,temp.PID_timestamp);
        
        old_dc = temp.voltage_dc_trap;
        if(dt<20)
            % update DC based on PID calculation
            Pterm = error*kp;
            Iterm = error*ki*dt+temp.PID_Iterm;
            Dterm = (ycentroid-temp.PID_oldvalue)*kd/dt;
            new_dc = old_dc + Pterm + Iterm + Dterm;
        else
            % don't change if elapsed time has been too long
            new_dc = old_dc;
            Iterm = temp.PID_Iterm; % leave integrated value unchanged
        end

        % update DC setpoint
        set_dc(new_dc)

        % if box checked, rescale AC frequency as DC changes
        mhold_rescale_ac = find_ui_handle('mhold_rescale_ac',microscope_window_handle);
        rescale_ac = get(mhold_rescale_ac,'Value');
        if(rescale_ac==1)
            freqfactor = abs(sqrt(1/(new_dc/old_dc)));
            % get current state of ac frequency
            old_ac = getappdata(main,'freq_ac_trap');
            new_ac = freqfactor*old_ac;
            % keep above 100 Hz and below 500 Hz
            new_ac = max([100 new_ac]);
            new_ac = min([500 new_ac]);
            % override new AC frequency if voltage is less than 5 V (it is too
            % agressive in this region as it is based on relative change)
            if(abs(new_dc<=5))
               new_ac = old_ac;
            end
            % update AC frequency
            set_ac_freq(new_ac);
        end
        
        % update globals used in next function call
        setappdata(main,'PID_timestamp',currenttime);
        setappdata(main,'PID_oldvalue',ycentroid);
        setappdata(main,'PID_Iterm',Iterm);
    end

    function setidealY(source,eventdata)
        setappdata(main,'IdealY',str2num(get(source,'string')))
    end

%% functions that actually do stuff for fringe camera
    function fringe_fullscreen(source,eventdata)
        temp = getappdata(main);
        preview(temp.fringe_video_handle)
        set(source,'value',0)
    end

    function fringe_camera_arm(source,eventdata)
    % FRINGE_CAMERA_ARM  Toggle arm state of fringe camera.
    %
    %   Toggles camera2Flag global state and appropriate UI camera controls.

        fgain_auto = find_ui_handle('fgain_auto',fringe_window_handle);
        fstatus_display = find_ui_handle('fstatus_display',...
            fringe_window_handle);
        ffullscreen_button = find_ui_handle('ffullscreen_button',...
            fringe_window_handle);
        fgain_slider = find_ui_handle('fgain_slider',fringe_window_handle);
        fshutter_slider = find_ui_handle('fshutter_slider',...
            fringe_window_handle);
        if(get(source,'value'))
            % turn camera flag on
            setappdata(main,'camera2Flag',1)
            % toggle ui controls
            fgain_auto.Enable = 'off';
            set(fstatus_display,'string','Camera Armed');
            set(fstatus_display,'backgroundcolor',[0.5 1 0.5]);
            set(ffullscreen_button,'visible','off')
            set(fgain_slider,'visible','off')
            set(fshutter_slider,'visible','off')
        else
            % turn camera flag off
            setappdata(main,'camera2Flag',0)
            % toggle ui controls
            set(fstatus_display,'string','Camera Ready');
            set(fstatus_display,'backgroundcolor',[1 0.5 0.5]);
            fgain_auto.Enable = 'on';
            set(ffullscreen_button,'visible','on')
            set(fgain_slider,'visible','on')
            set(fshutter_slider,'visible','on')
        end
    end

    function change_fringe_gain(source,eventdata)
    % CHANGE_FRINGE_GAIN  Change fringe camera gain based on slider value.
    %
    %   Write value to camera, update display string, and update image.

        temp = getappdata(main);
        fgain_slider = find_ui_handle('fgain_slider',fringe_window_handle);
        newgain = get(fgain_slider,'value');
        % write value to camera
        temp.fringe_source_data.Gain = newgain;
        % update display string
        fgain_display = find_ui_handle('fgain_display',fringe_window_handle);
        new_gain_str = [num2str(newgain,'%10.1f') ' dB'];
        set(fgain_display,'string',new_gain_str);
        % write source data back to application data
        setappdata(main,'fringe_source_data',temp.fringe_source_data);
        % update image
        wait_a_second(fringe_window_handle);
        frame = getsnapshot(temp.fringe_video_handle);
        frame_small = imresize(frame,[480 640]);
        good_to_go(fringe_window_handle);
        fcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax2'},...
            fringe_window_handle);
        imshow(frame_small,'parent',fcamera_ax);
    end

    function change_fringe_shutter(source,eventdata)
    % CHANGE_FRINGE_SHUTTER  Change fringe shutter speed based on slider value.
    %
    %   Write value to camera, update display string, and update image.

        temp = getappdata(main);
        fshutter_slider = find_ui_handle('fshutter_slider',...
            fringe_window_handle);
        newshutter = get(fshutter_slider,'value');
        % write value to camera
        temp.fringe_source_data.Shutter = newshutter;
        % update display string
        fshutter_display = find_ui_handle('fshutter_display',...
            fringe_window_handle);
        new_shutter_str = [num2str(newshutter,'%10.3f') ' ms'];
        set(fshutter_display,'string',new_shutter_str)
        % write source data back to application data
        setappdata(main,'fringe_source_data',temp.fringe_source_data);
        % update image
        wait_a_second(fringe_window_handle);
        frame = getsnapshot(temp.fringe_video_handle);
        frame_small = imresize(frame,[480 640]);
        good_to_go(fringe_window_handle);
        fcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax2'},...
            fringe_window_handle);
        imshow(frame_small,'parent',fcamera_ax);
    end

    function [imdata_compressed] = fringe_annotation(imdata)
    % FRINGE_ANNOTATION  Calculate and plot horizontal fringes in imdata.
    %
    %   Analysis assumes fringes are perfectly horizontal.
    %
    %   Returns:
    %   --------
    %   imdata_compressed : uint8 1D array
    %   Array of mean intensity of each row in imdata, scaled to 200.

        % take mean along each row
        imdata_compressed = mean(imdata,2);
        % rescale to 200
        imdata_compressed = uint8(imdata_compressed./max(imdata_compressed)*200);
        % overlay trace on fringe camera image
        fcamera_ax = find_ui_handle({'tgroup1','tg1t1','ax2'},...
            fringe_window_handle);
        plot(fcamera_ax,640-uint16(imdata_compressed(1:end)),1:(480),...
            'r','linewidth',2);
    end

%% functions that actually do stuff for arduino
    function arduino_mode(source,eventdata)
        temp = getappdata(main);
        %update app data with new UPSI to display
        setappdata(main,'UPSInumber',str2num(get(eventdata.NewValue,'String')));
    end

    function arduinocomms(source,eventdata)
    % ARDUINOCOMMS  Open or close connection to arduino.

        temp = getappdata(main);
        arduino_selectbox = find_ui_handle('arduino_selectbox',...
            arduino_window_handle);
        arduino_openclose = find_ui_handle('arduino_openclose',...
            arduino_window_handle);
        inject_pushbutton = find_ui_handle('inject_pushbutton',...
            arduino_window_handle);
        burst_pushbutton = find_ui_handle('burst_pushbutton',...
            arduino_window_handle);
        dcoffs = find_ui_handle('DCOFFS',microscope_window_handle);
        dc_buttons = {'DC OFFS +10','DC OFFS +1','DC OFFS +0.1',...
            'DC OFFS -10','DC OFFS -1','DC OFFS -0.1','DCOFFS_set0'};
        if(get(source,'value')) % initiate connection
            %open the port and lock the selector
            %get identity of port
            portstrings = get(arduino_selectbox,'string');
            portID = portstrings{get(arduino_selectbox,'value')};
            
            % Find a serial port object.
            obj2 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj2)
                obj2 = serial(portID);
            else
                fclose(obj2);
                obj2 = obj2(1);
            end
            set(obj2,'Timeout',1); %do a 1 second timeout
            
            %open the serial object and give time for Arduino to reset
            fopen(obj2);
            % if pause isn't long enough, fscanf call below won't receive
            % anything
            pause(2)
            % update and activate software controls
            set(arduino_selectbox,'enable','off');
            set(arduino_openclose,'string','Port Open');
            set(inject_pushbutton,'enable','on');
            set(burst_pushbutton,'enable','on');
            setappdata(main,'arduino_comm',obj2);

            % read UPSI RH/T data and update display
            update_rh_t()
            
            % turn things on for DC control (Union used 2nd SRS DS345)
            % ask arduino what setpoint was
            pause(1)
            flushinput(obj2) % clear any residual input from Arduino
            fprintf(obj2,'d');
            prev_dc_frac_str = fscanf(obj2,'%s\r\n');
            prev_dc_frac = str2num(prev_dc_frac_str);
            if isempty(prev_dc_frac)
                ME = MException('arduinocomms:noDacSetpoint', ...
                    ['Did not receive DAC setpoint from Arduino. ', ...
                    'Skipping rest of arduinocomms setup.']);
                % throwing exception exits arduinocomms() function call
                throw(ME);
            end
            % convert 12-bit setpoint to voltage
            prev_dc = prev_dc_frac*FULLRANGE_DC/4095;
            temp.voltage_dc_trap = prev_dc;
            setappdata(main,'voltage_dc_trap',temp.voltage_dc_trap);
            % Update displayed voltage setpoint
            new_dc_str = [num2str(prev_dc,'%+04.1f') ' V'];
            set(dcoffs,'string',new_dc_str);
            % turn on all DC increment buttons
            for tag_name = dc_buttons
                dc_button_handle = find_ui_handle(tag_name{:},...
                    microscope_window_handle);
                set(dc_button_handle,'enable','on')
            end
            
        else % close connection
            temp = getappdata(main);
            if(isfield(temp,'arduino_comm'))
                fclose(temp.arduino_comm);
                rmappdata(main,'arduino_comm');
            end
            set(arduino_selectbox,'enable','on');
            set(arduino_openclose,'string','Port Closed');
            set(inject_pushbutton,'enable','off');
            set(burst_pushbutton,'enable','off');
            
            % turn things off for DC control
            % disable DC control buttons
            for tag_name = dc_buttons
                dc_button_handle = find_ui_handle(tag_name{:},...
                    microscope_window_handle);
                set(dc_button_handle,'enable','off')
            end
            % return voltage_dc_trap to uninitialized value of -1
            setappdata(main,'voltage_dc_trap',-1);
        end
        
    end

    function update_rh_t_display()
    % UPDATE_RH_T_DISPLAY  Update humidity and temperature plots.
    %
    %   Plots are raw analog voltage readings from Arduino, 0 to 1023 scale.

        temp = getappdata(main);
        rh_ax = find_ui_handle('ax21',arduino_window_handle);
        temp_ax = find_ui_handle('ax20',arduino_window_handle);

        % do not attempt to plot if there is only one data point
        if(~isfield(temp,'UPSIdata')||size(temp.UPSIdata,1)==1)
            return
        end

        % plot temperature data (lower axis)
        plot(temp_ax,...
            temp.UPSIdata(:,1),...
            temp.UPSIdata(:,1+(temp.UPSInumber-1)*2+1),...
            '.');

        % format x axis ticks and labels (bottom of temperature plot)
        NumTicks = 6;
        L =[temp.UPSIdata(1,1) temp.UPSIdata(end,1)];
        set(temp_ax,'XTick',linspace(L(1),L(2),NumTicks))
        % Format DD.HH if multiple days of data, otherwise HH:MM
        if(diff(str2num(datestr(L,'DD')))>0)
            datetick(temp_ax,'x','(DD).HH','keepticks')
        else
            datetick(temp_ax,'x','HH:MM','keepticks')
        end

        % plot humidity data (upper axis)
        plot(rh_ax,...
            temp.UPSIdata(:,1),...
            temp.UPSIdata(:,1+(temp.UPSInumber-1)*2+2),...
            '.');
    end

    function update_rh_t()
    % UPDATE_RH_T  Query Arduino for RH and T values, record, and display.
    %
    %   Values are raw Arduino analog readings, 0 to 1023 scale.

        temp = getappdata(main);
        if(temp.arduino_comm.BytesAvailable~=0)
            flushinput(temp.arduino_comm);
        end
        [data2,~,msg] = query(temp.arduino_comm, 'r');
        if(~isempty(data2))
            try
                spaces = strfind(data2,' ');
                H1 = str2num(data2(1:spaces(1)-1));
                T1 = str2num(data2(spaces(1)+1:spaces(2)-1));
                H2 = str2num(data2(spaces(2)+1:spaces(3)-1));
                T2 = str2num(data2(spaces(3)+1:spaces(4)-1));
                % either append to existing array or create new array
                if(isfield(temp,'UPSIdata'))
                    temp.UPSIdata(end+1,:) = [now H1 T1 H2 T2];
                else
                    temp.UPSIdata(1,:) = [now H1 T1 H2 T2];
                end
                setappdata(main,'UPSIdata',temp.UPSIdata);
                update_rh_t_display();
            catch ME
                disp('problem with update_rh_t():')
                disp('Arduino response:')
                disp(data2)
                disp('not recording this RH/T response')
            end
        else
            % something went wrong. probably timed out. display warning message
            % and don't try to append to UPSIdata to avoid size mismatch error.
            disp('did not receive RH & T from Arduino. Warning message:')
            disp(msg)
        end
    end

    function inject(source,eventdata)
    % INJECT  Send inject command to Arduino and display timestamp.

        temp = getappdata(main);
        % send command
        data2 = query(temp.arduino_comm,'s');
        % update display
        inject_display = find_ui_handle('inject_display',...
            arduino_window_handle);
        set(inject_display,'string',[datestr(now) ' ' data2])
    end

    function burst(source,eventdata)
    % BURST  Send burst command of 20 drops to Arduino and display timestamp.

        temp = getappdata(main);
        inject_display = find_ui_handle('inject_display',...
            arduino_window_handle);
        % send command
        data2 = query(temp.arduino_comm,'1');
        % read remaining 19 lines returned from Arduino ("1","2",...,"19")
        for i = 1:19
            data2 = fgets(temp.arduino_comm);
        end
        set(inject_display,'string',[datestr(now) ' Burst'])
    end

    function set_dc(dc_trap)
        %Update trap DC setpoint by performing 3 tasks:
        %(1) Set DC voltage with the Arduino.
        %(2) Update DC setpoint state stored in 'main.voltage_dc_trap'
        %(3) Update display string, which is just for display.

        % send DC setpoint to Arduino with MCP4725 DAC installed
        % assumes 12-bit DAC with 0 to +5 V full range output, which is
        % then amplified to the full scale of the voltage supply
        % input:
        % dc_trap : float
        % Desired voltage across DC endcaps in trap
        temp = getappdata(main);
        % check voltage is in range
        if dc_trap>=0 && dc_trap<=FULLRANGE_DC
            allbits = round(dc_trap/FULLRANGE_DC * 4095);
            % first byte is 0b1xxx#### where 1 is flag for Arduino that
            % this is the first byte of a DC voltage setpoint, xxx is
            % discarded and #### are the highest 4 bits of the 12-bit
            % setpoint.
            setpointflag = hex2dec('80');
            highbits = bitand(allbits,bin2dec('111100000000'));
            firstbyte = setpointflag + bitshift(highbits,-8);
            secondbyte = bitand(allbits,bin2dec('000011111111'));

            % send bytes to arduino. It's important they're sent as single
            % bytes, without any newline character!
            % also read expected responses from arduino. If the responses
            % don't exist, there must have been a timeout problem.
            fwrite(temp.arduino_comm,firstbyte);
            % expect to receive "First 4 dac bits"
            [tline1,~,msg1] = fgets(temp.arduino_comm);
            if(isempty(tline1))
                disp('After sending first 4 DAC bits, no Arduino response.')
                disp('Resulted in following warning:')
                warning(msg1)
            end

            fwrite(temp.arduino_comm,secondbyte);
            % expect to receive "Last 8 dac bits" and "dacSetpoint: xxxx"
            [tline2,~,msg2] = fgets(temp.arduino_comm);
            if(isempty(tline2))
                disp('After sending last 8 DAC bits, no 1st Arduino response.')
                disp('Resulted in following warning:')
                warning(msg2)
            end
            [tline3,~,msg3] = fgets(temp.arduino_comm);
            if(isempty(tline3))
                disp('After sending last 8 DAC bits, no 2nd Arduino response.')
                disp('Resulted in following warning:')
                warning(msg3)
            end
        else
            ME = MException('set_dc:voltageOutOfRange', ...
                'voltage setpoint out of range');
            throw(ME);
        end

        % display new DC setpoint in microscope window
        dcoffs = find_ui_handle('DCOFFS',microscope_window_handle);
        new_dc_str = [num2str(dc_trap,'%+04.1f') ' V'];
        dcoffs.String = new_dc_str;

        % update voltage_dc_trap
        temp.voltage_dc_trap = dc_trap;
        setappdata(main,'voltage_dc_trap',temp.voltage_dc_trap);
    end

    function increment_dc(source,eventdata,dc_increment)
    % INCREMENT_DC  Increment trap DC setpoint after button press.

        old_dc = getappdata(main,'voltage_dc_trap');
        new_dc = old_dc+dc_increment;
        set_dc(new_dc)

    end

    function zero_dc(source,eventdata)
    % ZERO_DC  Set trap DC setpoint to zero after button press.
    %
    %   Wrapper around set_dc(0) call, written as callback (source, eventdata
    %   args)

        set_dc(0)
    end
        
%% functions that actually do stuff for the SRS function generator
    function srscomms(source,eventdata)
    % SRSCOMMS  Open or close connection to SRS function generator.

        srs2selectbox = find_ui_handle('SRS2selectbox',...
            microscope_window_handle);
        ac_buttons = {'AC FREQ +10','AC FREQ +1','AC FREQ +0.1',...
            'AC FREQ -10','AC FREQ -1','AC FREQ -0.1','AC AMP  +0.1',...
            'AC AMP  +0.01','AC AMP  -0.01','AC AMP  -0.1','eject_button'};
        if(get(source,'value'))
            stop(fasttimer)

            % get identity of port and set up device connection
            portstrings = get(srs2selectbox,'string');
            portID = portstrings{get(srs2selectbox,'value')};
            DS345_AC = DS345Device(portID);
            setappdata(main,'DS345_AC',DS345_AC);
            set(srs2selectbox,'enable','off');
            set(source,'string','Port Open');

            % initialize AC amp and freq to SRS values
            % amplitude is string terminating with 'VP'
            existing_amp_str = DS345_AC.amplitude;
            existing_amp = str2double(existing_amp_str(1:end-2));
            set_ac_amp(existing_amp);
            existing_freq = str2double(DS345_AC.frequency);
            set_ac_freq(existing_freq);

            % enable AC buttons
            for tag_name = ac_buttons
                handle = find_ui_handle(tag_name{:},microscope_window_handle);
                handle.Enable = 'on';
            end

            start(fasttimer)
        else
            % close port and clean up application data
            temp = getappdata(main);
            temp.DS345_AC.delete;
            rmappdata(main,'DS345_AC');

            % update display
            set(srs2selectbox,'enable','on');
            set(source,'string','Port Closed');
            for tag_name = ac_buttons
                handle = find_ui_handle(tag_name{:},microscope_window_handle);
                handle.Enable = 'off';
            end

            % return state variablse to uninitialized values of -1
            setappdata(main,'amp_ac_trap',-1);
            setappdata(main,'freq_ac_trap',-1);
        end
    end

    function set_ac_freq(freq)
    % SET_AC_FREQ  Update trap AC frequency setpoint.
    %
    %   Perform 3 tasks:
    %   (1) Set AC frequency with the SRS function generator.
    %   (2) Update display string, which is just for display.
    %   (3) Update AC frequency setpoint state in 'main.freq_ac_trap'

        % set actual frequency using SRS DS345 serial object
        % note set_freq requires a string input
        ds345 = getappdata(main,'DS345_AC');
        ds345.set_freq(num2str(freq));

        % display new setpoint in microscope window
        ac_freq_handle = find_ui_handle('ACFREQ',microscope_window_handle);
        ac_freq_handle.String = [num2str(freq,'%04.1f') ' Hz'];

        % update freq_ac_trap
        setappdata(main,'freq_ac_trap',freq);
    end

    function set_ac_amp(amp)
    % SET_AC_AMP  Update trap AC amplitude (Vpp, pre-amplified) setpoint.
    %
    %   Perform 3 tasks:
    %   (1) Set AC amplitude with the SRS function generator.
    %   (2) Update display string, which is just for display.
    %   (3) Update AC amplitude setpoint state in 'main.amp_ac_trap'

        % set actual amplitude using SRS DS345 serial object
        % note set_amp requires a string input
        ds345 = getappdata(main,'DS345_AC');
        ds345.set_amp(num2str(amp),'VP');

        % display new setpoint in microscope window
        ac_amp_handle = find_ui_handle('ACAMP',microscope_window_handle);
        ac_amp_handle.String = [num2str(amp,'%.2f') ' VP'];

        % update amp_ac_trap
        setappdata(main,'amp_ac_trap',amp);
    end

    function increment_ac_amp(source,eventdata,amp_increment)
    % INCREMENT_AC_AMP  Increment AC amplitude on button press.

        old_amp = getappdata(main,'amp_ac_trap');
        new_amp = old_amp+amp_increment;
        set_ac_amp(new_amp);
    end

    function increment_ac_freq(source,eventdata,freq_increment)
    % INCREMENT_AC_FREQ  Increment AC frequency on button press.

        old_freq = getappdata(main,'freq_ac_trap');
        new_freq = old_freq+freq_increment;
        set_ac_freq(new_freq);
    end

    function eject_particle(source,eventdata)
    % EJECT_PARTICLE  Set AC amplitude to 0 for user-defined amount of time.

        eject_length = find_ui_handle('eject_length',microscope_window_handle);
        eject_time = str2double(eject_length.String);
        current_ac_amp = getappdata(main,'amp_ac_trap');

        set_ac_amp(0);

        pause(eject_time);

        set_ac_amp(current_ac_amp);
    end


%% functions that actually do stuff for the MKS and Lauda board

    function Laudacomms(source,eventdata)
        laudaselectbox = find_ui_handle('laudaselectbox',MKS_window_handle);
        laudaopenclose = find_ui_handle('laudaopenclose',MKS_window_handle);
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            
            portstrings = get(laudaselectbox,'string');
            portID = portstrings{get(laudaselectbox,'value')};
            
            set(mksselectbox,'enable','off');
            set(laudaopenclose,'string','Port Open');
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            set(obj1, 'Terminator', {'CR/LF','CR/LF'});
            
            % Connect to instrument object, obj1.
            fopen(obj1);
            setappdata(main,'LaudaRS232',obj1)
            
            update_Lauda(0)
        else
            % toggle ui controls
            lauda_on_off = find_ui_handle('Lauda_on_off',MKS_window_handle);
            lauda_chiller_on_off = find_ui_handle('Lauda_chiller_on_off',...
                MKS_window_handle);
            lauda_t_controlbutton = find_ui_handle('Lauda_T_controlbutton',...
                MKS_window_handle);
            lauda_set_t = find_ui_handle('Lauda_set_T',MKS_window_handle);
            set(laudaselectbox,'enable','on');
            set(laudaopenclose,'string','Port Closed');
            set(lauda_on_off,'enable','off');
            set(lauda_chiller_on_off,'enable','off');
            set(lauda_t_controlbutton,'enable','off');
            set(lauda_set_t,'enable','off');
            % close serial port and remove instrument object
            temp = getappdata(main);
            fclose(temp.LaudaRS232);
            rmappdata(main,'LaudaRS232');
        end
    end

    function update_Lauda(savelogic)
        lauda_on_off = find_ui_handle('Lauda_on_off',MKS_window_handle);
        lauda_chiller_on_off = find_ui_handle('Lauda_chiller_on_off',...
            MKS_window_handle);
        lauda_t_controlbutton = find_ui_handle('Lauda_T_controlbutton',...
            MKS_window_handle);
        lauda_set_t = find_ui_handle('Lauda_set_T',MKS_window_handle);
        lauda_reported_t = find_ui_handle('Lauda_reported_T',MKS_window_handle);
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        temp = getappdata(main);
        obj1 = temp.LaudaRS232;

        data8 = query(obj1, 'STATUS');
        if(str2num(data8)~=0)
            error('Lauda communication failure')
        end
        
        % read power status
        onoff = query(obj1, 'IN_MODE_02');
        if(str2num(onoff)==1)
            % pump is off
            set(lauda_on_off,'string','Pump off','Value',0,'enable','on')
        else
            % pump is on
            set(lauda_on_off,'string','Pump on','value',1,'enable','on')
        end
        
        cooleronoff = query(obj1,'IN_SP_02');
        if(str2num(cooleronoff)==2)
            % automatic
            set(lauda_chiller_on_off,'string','Chiller Auto','Value',1,...
                'enable','on');
        elseif(str2num(cooleronoff)==0)
            % off
            set(lauda_chiller_on_off,'string','Chiller Off','Value',0,...
                'enable','on');
        else
            error('unrecognized cooler mode!')
        end
        
        controler_internalvsexternal = query(obj1,'IN_MODE_01');
        if(str2num(controler_internalvsexternal)==1)
            %automatic
            set(lauda_t_controlbutton,'string','Control via PT100',...
                'Value',1,'enable','on');
        elseif(str2num(controler_internalvsexternal)==0)
            %off
            set(lauda_t_controlbutton,'string','Control via Bath',...
                'Value',0,'enable','on');
        else
            error('unrecognized control mode!')
        end
        
        
        %read current T setpoint
        setT = query(obj1, 'IN_SP_00');
        
        setT = strtrim(setT);
        
        if(setT(1)=='0')
            setT(1) = [];
        end
        
        set(lauda_set_t,'string',setT,'enable','on')
        
        actualT = query(obj1, 'IN_PV_00');
        
        actualT = strtrim(actualT);
        
        if(actualT(1)=='0')
           actualT(1) = []; 
        end
        
        externalT = query(obj1, 'IN_PV_03');
        
        externalT = strtrim(externalT);
        
        if(externalT(1)=='0')
           externalT(1) = []; 
        end
        
        set(lauda_reported_t,'string',['Int:' actualT ' Ext: ' externalT],...
            'enable','on')
        
        hum_table.Data(1,2) = str2num(setT);
        
        temp.Laudadatalog(end+1,:) = [now str2num(onoff) str2num(setT) str2num(actualT) str2num(externalT)];
        if(savelogic)
            setappdata(main,'Laudadatalog',temp.Laudadatalog);
        end
    end

    function LaudaPower(source,eventdata)
        temp = getappdata(main);
        lauda_on_off = find_ui_handle('Lauda_on_off',MKS_window_handle);
        obj1 = temp.LaudaRS232;
        if(get(source,'value'))
            qd = query(obj1,'START');
            set(lauda_on_off,'string','Pump on')
        else
            qd = query(obj1,'STOP');
            set(lauda_on_off,'string','Pump off')
        end
    end

    function LaudaChiller(source,eventdata)
        temp = getappdata(main);
        lauda_chiller_on_off = find_ui_handle('Lauda_chiller_on_off',...
            MKS_window_handle);
        obj1 = temp.LaudaRS232;
        if(get(source,'value'))
            qd = query(obj1,'OUT_SP_02_02');
            set(lauda_chiller_on_off,'string','Chiller auto')
        else
            qd = query(obj1,'OUT_SP_02_00');
            set(lauda_chiller_on_off,'string','Chiller off')
        end
    end

    function LaudaControl(source,eventdata)
        temp = getappdata(main);
        lauda_t_controlbutton = find_ui_handle('Lauda_T_controlbutton',...
            MKS_window_handle);
        obj1 = temp.LaudaRS232;
        if(get(source,'value'))
            qd = query(obj1,'OUT_MODE_01_1');
            set(lauda_t_controlbutton,'string','Control via PT100')
        else
            qd = query(obj1,'OUT_MODE_01_0');
            set(lauda_t_controlbutton,'string','Control via Bath')
        end
    end

    function Lauda_send_T(source,eventdata,varargin)
        if(length(varargin)==0)
            setT = str2num(get(source,'string'));
        else
            setT = varargin{1};
        end
        %TODO: add saftey feature to prevent user from typing in something dumb
        temp = getappdata(main);
        obj1 = temp.LaudaRS232;
        qd = query(obj1,['OUT_SP_00_' num2str(setT,'%5.2f')]);
    end

    function Julabocomms(source,eventdata)
        julaboselectbox = find_ui_handle('Julaboselectbox',MKS_window_handle);
        julaboopenclose = find_ui_handle('Julaboopenclose',MKS_window_handle);
        if(get(source,'value'))
            stop(fasttimer)
            %get identity of port
            
            portstrings = get(julaboselectbox,'string');
            portID = portstrings{get(julaboselectbox,'value')};
            
            set(julaboselectbox,'enable','off');
            set(julaboopenclose,'string','Port Open');
            
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            % Configure instrument object, obj1.
            set(obj1, 'Timeout', 1.0);
            
            % Configure instrument object, obj1.
            set(obj1, 'Terminator', {'CR/LF','CR'});
            
            obj1.DataBits = 7;
            obj1.FlowControl = 'hardware';
            obj1.Parity = 'even';
            obj1.BaudRate = 4800;
            
            % Connect to instrument object, obj1.
            fopen(obj1);
            setappdata(main,'JulaboRS232',obj1)
            
            update_Julabo(0)
        else
            % toggle ui elements
            julabo_reported_t = find_ui_handle('Julabo_reported_T',...
                MKS_window_handle);
            julabo_set_t = find_ui_handle('Julabo_set_T',MKS_window_handle);
            julabo_on_off = find_ui_handle('Julabo_on_off',MKS_window_handle);
            set(julaboselectbox,'enable','on');
            set(julaboopenclose,'string','Port Closed');
            set(julabo_set_t,'string','?','enable','off');
            set(julabo_reported_t,'string','?','enable','off');
            set(julabo_on_off,'string','Pump ?','Value',0,'enable','off');
            % close serial port and remove instrument object
            temp = getappdata(main);
            fclose(temp.JulaboRS232);
            rmappdata(main,'JulaboRS232');
        end
    end

    function update_Julabo(savelogic)
        julabo_set_t = find_ui_handle('Julabo_set_T',MKS_window_handle);
        julabo_reported_t = find_ui_handle('Julabo_reported_T',...
            MKS_window_handle);
        julabo_on_off = find_ui_handle('Julabo_on_off',MKS_window_handle);
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        temp = getappdata(main);
        obj1 = temp.JulaboRS232;
        data8 = query(obj1, 'status');
        if(strcmp(strtrim(data8),'03 REMOTE START')|strcmp(strtrim(data8),'02 REMOTE STOP'))
            %it's all good
        else
            error('Julabo communication failure')
        end
        
        % read power status
        onoff = query(obj1, 'in_mode_05');
        if(str2num(onoff)==0)
            %pump is off
            set(julabo_on_off,'string','Pump off','Value',0,'enable','on')
        else
            %pump is on
            set(julabo_on_off,'string','Pump on','value',1,'enable','on')
        end
        
        % read current T setpoint
        setT = query(obj1, 'in_sp_00');
        
        set(julabo_set_t,'string',setT(1:end-2),'enable','on')
        
        hum_table.Data(1,5) = str2num(setT(1:end-2));
        
        actualT = query(obj1, 'in_pv_00');
        
        set(julabo_reported_t,'string',actualT(1:end-2),'enable','on')
        
        temp.Julabodatalog(end+1,:) = [now str2num(onoff) str2num(setT) str2num(actualT)];
        if(savelogic)
            setappdata(main,'Julabodatalog',temp.Julabodatalog);
        end
    end

    function JulaboPower(source,eventdata)
        temp = getappdata(main);
        julabo_on_off = find_ui_handle('Julabo_on_off',MKS_window_handle);
        obj1 = temp.JulaboRS232;
        if(get(source,'value'))
            fprintf(obj1,'out_mode_05 1'); %start the pump
            set(julabo_on_off,'string','Pump on')
        else
            fprintf(obj1,'out_mode_05 0'); %stop the pump
            set(julabo_on_off,'string','Pump off')
        end
    end

    function Julabo_send_T(source,eventdata,varargin)
        if(length(varargin)==0)
            setT = str2num(get(source,'string'));
        else
            setT = varargin{1};
        end
        %TODO: add safety feature to prevent user from typing in something dumb
        temp = getappdata(main);
        obj1 = temp.JulaboRS232;
        fprintf(obj1,['out_sp_00 ' num2str(setT,'%5.2f')]);
    end


    function MKScomms(source,eventdata)
    % MKSCOMMS  Open or close serial communication with MKS 946 controller.
    %
    %   Serial object is set to main.MKS946_comm.

        bg3_toggleable = {'3','mks3_plus25','mks3_plus5','mks3_plus1',...
            'mks3_minus1','mks3_minus5','mks3_minus25'};
        bg4_toggleable = {'4','mks4_plus25','mks4_plus5','mks4_plus1',...
            'mks4_minus1','mks4_minus5','mks4_minus25'};
        mksselectbox = find_ui_handle('MKSselectbox',MKS_window_handle);
        mksopenclose = find_ui_handle('MKSopenclose',MKS_window_handle);
        % direct sending of commands to MKS was either deprecated or not fully
        % implemented
        mkssendbutton = find_ui_handle('MKSsendbutton',MKS_window_handle);
        if(get(source,'value'))
            % open port and lock selector
            % get port identity
            portstrings = get(mksselectbox,'string');
            portID = portstrings{get(mksselectbox,'value')};
            
            % Find a serial port object.
            obj1 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            
            % Create the serial port object if it does not exist
            % otherwise use the object that was found.
            if isempty(obj1)
                obj1 = serial(portID);
            else
                fclose(obj1);
                obj1 = obj1(1);
            end
            
            set(obj1, 'Terminator', {70,''});
            set(obj1,'Timeout',1); %do a 1 second timeout
            %open the serial object
            fopen(obj1);
            setappdata(main,'MKS946_comm',obj1)

            set(mksselectbox,'enable','off');
            set(mksopenclose,'string','Port Open');
            set(mkssendbutton,'enable','on');
            for tag_name = bg3_toggleable
                bg3_handle = find_ui_handle({'bg3',tag_name{:}},...
                    MKS_window_handle);
                set(bg3_handle,'enable','on')
            end
            for tag_name = bg4_toggleable
                bg4_handle = find_ui_handle({'bg4',tag_name{:}},...
                    MKS_window_handle);
                set(bg4_handle,'enable','on')
            end

            update_MKS_values(source,eventdata,0)
            
        else
            %close the port and unlock the selector
            %check app data
            temp = getappdata(main);
            if(isfield(temp,'MKS946_comm'))
                fclose(temp.MKS946_comm);
                rmappdata(main,'MKS946_comm');
            end

            set(mksselectbox,'enable','on');
            set(mksopenclose,'string','Port Closed');
            set(mkssendbutton,'enable','off');
            for tag_name = bg3_toggleable
                bg3_handle = find_ui_handle({'bg3',tag_name{:}},...
                    MKS_window_handle);
                set(bg3_handle,'enable','off')
            end
            for tag_name = bg4_toggleable
                bg4_handle = find_ui_handle({'bg4',tag_name{:}},...
                    MKS_window_handle);
                set(bg4_handle,'enable','off')
            end
        end
        
    end

    function update_MKS_values(source,eventdata,savelogic)
    % UPDATE_MKS_VALUES  Update values for MKS controller.
    %
    %   Dispatched as part of datalogic branch of fasttimerFcn.

        mks3_r1 = find_ui_handle({'bg3','mks3_r1'},MKS_window_handle);
        mks3_r2 = find_ui_handle({'bg3','mks3_r2'},MKS_window_handle);
        mks3_r3 = find_ui_handle({'bg3','mks3_r3'},MKS_window_handle);
        mks3sp = find_ui_handle({'bg3','3'},MKS_window_handle);
        mks3act = find_ui_handle({'bg3','mks3act'},MKS_window_handle);

        mks4_r1 = find_ui_handle({'bg4','mks4_r1'},MKS_window_handle);
        mks4_r2 = find_ui_handle({'bg4','mks4_r2'},MKS_window_handle);
        mks4_r3 = find_ui_handle({'bg4','mks4_r3'},MKS_window_handle);
        mks4sp = find_ui_handle({'bg4','4'},MKS_window_handle);
        mks4act = find_ui_handle({'bg4','mks4act'},MKS_window_handle);

        hum_table = find_ui_handle('hum_table',MKS_window_handle);

        % query mode ('QMDn?') of ch3 and 4 (hard coded)
        md3 = MKSsend(source,eventdata,'QMD3?');
        switch md3
            case 'OPEN',
                mks3_r1.Value = 1;
                MKS3onoff = NaN;
            case 'CLOSE',
                mks3_r2.Value = 1;
                MKS3onoff = 0;
            case 'SETPOINT'
                mks3_r3.Value = 1;
                MKS3onoff = 1;
        end
        
        md4 = MKSsend(source,eventdata,'QMD4?');
        switch md4
            case 'OPEN',
                mks4_r1.Value = 1;
                MKS4onoff = NaN;
            case 'CLOSE',
                mks4_r2.Value = 1;
                MKS4onoff = 0;
            case 'SETPOINT'
                mks4_r3.Value = 1;
                MKS4onoff = 1;
        end
        
        % query ch4 setpoint
        sp4 = MKSsend(source,eventdata,'QSP4?');
        F_humid = str2num(sp4)*MKS4onoff;
        % format setpoint as string and (probably?) update textbox
        sp4_str = sprintf('%.2f',str2num(sp4));
        set(mks4sp,'string',sp4_str(1:4));
        
        % query ch3 setpoint
        sp3 = MKSsend(source,eventdata,'QSP3?');
        F_dry = str2num(sp3)*MKS3onoff;
        sp3_str = sprintf('%.2f',str2num(sp3));
        set(mks3sp,'string',sp3_str(1:4));
        
        % fill in values of table
        hum_table.Data(1,4) = F_dry+F_humid;
        
        % query ch3 and ch4 flow rates, update displayed values
        stat = MKSsend(source,eventdata,'FR3?');
        stat = sprintf('%.2f',str2num(stat));
        mks3act.String = [stat ' sccm'];
        
        stat = MKSsend(source,eventdata,'FR4?');
        stat = sprintf('%.2f',str2num(stat));
        mks4act.String = [stat ' sccm'];
        
        % calculate RH based on flow ratio and bath temperature
        % (assumes 19 C if not provided)
        if(hum_table.Data(1,2)~=-999)
            julabo_set_t = find_ui_handle('Julabo_set_T',MKS_window_handle);
            julabo_set_t_num = str2num(julabo_set_t.String)
            if(isa(julabo_set_t_num,'numeric'))
                Bath_T = julabo_set_t_num
            else
                Bath_T = 19;
            end
            Bath_saturation = water_vapor_pressure(Bath_T+273.15);
            Trap_saturation = water_vapor_pressure(hum_table.Data(1,2)+273.15);
            RH = round(100*F_humid/(F_humid+F_dry)*Bath_saturation/Trap_saturation,1);
            if(~isempty(RH))
                hum_table.Data(1,3) = RH;
            end
        end
        
        temp = getappdata(main);
        temp.MKSdatalog(end+1,:) = [now F_dry F_humid];
        if(savelogic)
            setappdata(main,'MKSdatalog',temp.MKSdatalog);
        end
    end

    function [response] = MKSsend(source,eventdata,varargin)
    % MKSSEND  Send message to MKS controller and return response.
    %   MKS 946 query string format: @<aaa><Command>?;FF
    %   <aaa> is address, 1 to 254
    %   string within varargin becomes <Command>
    %   MKS 946 response string format: @<aaa>ACK<Response>;FF
    %   Common commands are QMDn, QSPn, FRn. See MKS manual for full list.

        temp = getappdata(main);
        mkscommandline = find_ui_handle('MKScommandline',MKS_window_handle);
        mksresponse = find_ui_handle('MKSresponse',MKS_window_handle);
        % if varargin is passed, use that as <Command>. otherwise use string in
        % MKScommandline
        if(length(varargin)==1)
            arg1 = varargin{1};
        else
            arg1 = mkscommandline.String;
        end

        querytext = ['@253' arg1 ';FF'];
        data1 = query(temp.MKS946_comm, querytext);
        if(data1=='F')
            warning([datestr(now) ' MKS946 out of sequence. Performing '...
                'additional read. (Command=' arg1 ')'])
            data1 = fscanf(temp.MKS946_comm);
        end
        if(isempty(data1))
            error('No data returned by MKS RS232')
        end
        % not sure why this additional read happens... (AWB 17 Apr 2018)
        data2 = fscanf(temp.MKS946_comm);
        % check for errors
        if(strcmp(data1(5:7),'NAK'))
            error('Communication error to MKS!')
        end
        % return and display <Response> from response string (see format above)
        response = data1(8:end-2);
        set(mksresponse,'string',data1)
    end

    function MKS_mode(source,eventdata)
        %figure out where the button push happened
        % assumes tags is 'bg3 or 'bg4'
        pan_num_tag = get(source,'tag');
        pan_num = pan_num_tag(3:end);
        selection = [];
        if(strcmp(upper(get(eventdata.NewValue,'String')),'OPEN'))
            selection = questdlg('Really OPEN valve?','Run OPEM valve?',...
                'Yes','No','No');
        end
        
        if(~isempty(selection))
            switch selection
                case 'Yes',
                    %let it  run
                case 'No'
                    source.Children(3).Value = 0;
                    source.Children(4).Value = 0;
                    source.Children(5).Value = 0;
                    return
            end
        end
        MKSsend(source,eventdata,['QMD' pan_num '!' upper(get(eventdata.NewValue,'String'))]);
    end


    function MKSchangeflow(source,eventdata,channel,value)
    % MKSCHANGEFLOW  Change flow setpoint on `channel` to `value`.
    %
    %   If `value` is nan, flow setpoint is the String property of the callback
    %   `source`. Otherwise flow setpoint is `value`, which is assumed to be
    %   a float.
    %
    %   Throws an exception if value is less than 0 or larger than a hard-coded
    %   max flow rate for the given channel.

        % if passed value is nan, replace with String property of source
        if(isnan(value))
            value = str2num(get(source,'string'));
        end
        % right now, max flow rates are hard-coded
        if(channel==3)
            max_flow = 1000;
        elseif(channel==4)
            max_flow = 200;
        else
            error('MKSchangeflow: bad channel number input')
        end
        if(value>=0 && value<=max_flow)
            % format value as d.ddE+ee for serial message to MFC controller
            formatted_value = sprintf('%.2E',value);
            qsp_command = ['QSP' num2str(channel) '!' formatted_value];
            MKSsend(source,eventdata,qsp_command);
        else
            ME = MException('MKSchangeflow:flowOutOfRange', ...
                'flow setpoint out of range');
            throw(ME);
        end
    end

    function mks_increment(source,eventdata,channel,incr)
    % MKS_INCREMENT  Increment flow setpoint on `channel` by `incr`.
        stop(fasttimer)
        if(channel==3)
            setpoint_handle = find_ui_handle({'bg3','3'},MKS_window_handle);
        elseif(channel==4)
            setpoint_handle = find_ui_handle({'bg4','4'},MKS_window_handle);
        else
            error('mks_increment: bad channel argument')
        end
        old_flow = str2double(setpoint_handle.String);
        new_flow = old_flow + incr;
        setpoint_handle.String = num2str(new_flow);
        MKSchangeflow(source,eventdata,channel,new_flow);
        start(fasttimer)
    end

    function p_circ = water_vapor_pressure(T)
        
        %http://www.watervaporpressure.com/
        %input T in celsius!
        %output in torr
        %A = 8.07131;
        %B = 1730.64;
        %C = 233.426;
        %RANGE: 1-100 degC
        
        %http://webbook.nist.gov/cgi/cbook.cgi?ID=C7732185&Mask=4&Type=ANTOINE&Plot=on#ref-4
        %Stull, 1947
        %T in Kelvin
        %P in bar
        A = 4.6543;
        B = 1435.264;
        C = -64.848;
        
        p_circ = 10.^(A-(B./(C+T)));
        
    end

    function cleartable_fcn(source,eventdata)
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        hum_table.Data = [0 -999 -999 -999];
    end

    function edit_table(source,eventdata)
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        data = hum_table.Data;
        hum_table.Data = data;
    end

    function addrow_fcn(source,eventdata)
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        data = hum_table.Data;
        data(end+1,:) = data(end,:); %if data is an array.
        data(end,1) = data(end,1)+0.5; %make default 30 minutes per step
        hum_table.Data = data;
    end

    function temp_fig = sim_ramp_fcn(source,eventdata)
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        data = hum_table.Data;
        fc1 = 200;
        fc2 = 200;
        %put in 10 points in between every one that the user requests
        for i = 0:size(data,1)-2
            newdata(i*10+1:i*10+10,:) = [linspace(data(i+1,1),data(i+2,1),10)' ...
                linspace(data(i+1,2),data(i+2,2),10)' ...
                linspace(data(i+1,3),data(i+2,3),10)' ...
                linspace(data(i+1,4),data(i+2,4),10)' ...
                linspace(data(i+1,5),data(i+2,5),10)'];
        end
        %repoint the data towards new data
        data = newdata;
        flow_total = data(:,4);
        Bath_T = data(:,5);
        p_source = water_vapor_pressure(Bath_T+273.15); %in bar
        p_trap_sat = water_vapor_pressure(data(:,2)+273.15); %in bar
        p_trap = p_trap_sat.*data(:,3)/100; %in bar
        maxRH = p_source./p_trap_sat;
        flows = [1-p_trap./p_source p_trap./p_source]; %unscaled flows
        over_range = flows>1;
        flows(over_range==1) = 1;
        under_range = flows<0;
        flows(under_range==1) = 0;
        flows = flows.*repmat(flow_total,size(flows)./size(flow_total));
        T_setpoints = data(:,2);
        Julabo_setpoints = data(:,5);
        dwpt_thy = water_dew_pt(flows(:,2)./sum(flows,2).*p_source)-273.15;
        temp_fig = figure('position',[100 100 600 700]);
        subplot(3,1,[1 2])
        [temp_ax,h1,h2] = plotyy(data(:,1),T_setpoints,data(:,1),p_trap./p_trap_sat*100);
        l2 = line(temp_ax(1),data(:,1),Julabo_setpoints);
        l3 = line(temp_ax(1),data(:,1),dwpt_thy);
        l1 = line(temp_ax(2),newdata(:,1),maxRH*100);
        set(l1,'linestyle',':','color','r');
        set(l3,'linestyle','-.','color','k')
        set(h2,'linestyle','--','color','r')
        set(l2,'linestyle','-','color',[0 0.5 0])
        
        xlabel('Time (hrs)')
        ylabel(temp_ax(1),'Temperature (°C)')
        legend(temp_ax(1),'Trap','Hookah','Dewpt','location','northwest')
         legend(temp_ax(2),'Trap RH','Max RH','location','northeast')
        ylabel(temp_ax(2),'RH in trap (%)')
        temp_ax(1).YLim = [min([data(:,2); Julabo_setpoints])-1 max([data(:,2); Julabo_setpoints])+1];
        temp_ax(1).YTickMode = 'Auto';
        temp_ax(2).YLim = [min([p_trap./p_trap_sat*100; maxRH*100])-5 max([[p_trap./p_trap_sat*100; maxRH*100]])+5];
        temp_ax(2).YTickMode = 'Auto';
        subplot(3,1,3)
        plot(data(:,1),flows(:,1),data(:,1),flows(:,2))
        xlabel('Time (hrs)')
        ylabel('Flow (sccm)')
        legend('Dry','Humid')
        
        if(any(dwpt_thy>33))
            warndlg('Dewpoint exceeds 33°C. Be careful!')
        end
        
        setappdata(main,'Ramp_data',unique([data(:,1) flows T_setpoints Julabo_setpoints],'rows'))
        %TODO: currently assumes everything is linear, but RH depends
        %nonlinearly on temperature...
    end



    function drive_ramps_fcn(source,eventdata)
        runramp_button = find_ui_handle('runramp_button',MKS_window_handle);
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        if(source.Value)
            stop(fasttimer)
            stop(errorcatchtimer)
            temp_fig = sim_ramp_fcn(source,eventdata);
            selection = questdlg('Run this ramp?','Run this ramp?',...
                'Yes','No','No');
            if(strcmp(selection,'Yes'))
                dt_str = inputdlg('Start ramp at what relative time?','Ramp time start',1,{'0'});
                dt_num = str2num(dt_str{1});
                set(hum_table,'enable','off')
                setappdata(main,'RampFlag',1)
                set(runramp_button,'string','Ramping...')
                setappdata(main,'RampTime_init',now-dt_num/24);
                close(temp_fig)
            else
                %turn button back off
                runramp_button.Value = 0;
            end
            start(fasttimer)
            start(errorcatchtimer)
        else
            set(hum_table,'enable','on')
            setappdata(main,'RampFlag',0)
            set(runramp_button,'string','Ramp Trap')
        end
    end



%% functions that actually do stuff for andor
    function andor_initalize(source,eventdata)
        %initalize camera
        %check to see if the camera is already connected
        wait_a_second(Andor_window_handle)
        [ret,status] = AndorGetStatus();
        if(status==atmcd.DRV_IDLE)
            %camera already connected, no need to reinitialize the connection
        else
            ret = AndorInitialize('');
        end
        good_to_go(Andor_window_handle)
        CheckError(ret);

        acooler = find_ui_handle('acooler',Andor_window_handle);
        acooleractualtext = find_ui_handle('acooleractualtext',...
            Andor_window_handle);
        acoolersettext = find_ui_handle('acoolersettext',Andor_window_handle);
        aloop_scan = find_ui_handle('aloop_scan',Andor_window_handle);
        astatus_selectbox = find_ui_handle('astatus_selectbox',...
            Andor_window_handle);
        a_kincyctime = find_ui_handle('a_kincyctime',Andor_window_handle);
        a_numkinseries = find_ui_handle('a_numkinseries',Andor_window_handle);
        a_integrationtime = find_ui_handle('a_integrationtime',...
            Andor_window_handle);
        aaqdata = find_ui_handle('aaqdata',Andor_window_handle);
        center_wavelength_selectbox = find_ui_handle('center_wavelength_selectbox',...
            Andor_window_handle);
        grating_selectbox = find_ui_handle('grating_selectbox',...
            Andor_window_handle);

        update_andor_output('Connected to Andor')
        % check and synchronize chiller status
        [ret,Cstat] = IsCoolerOn;
        setappdata(main,'AndorFlag',1)
        if(Cstat)
            %chiller is already on
            set(acooler,'value',1,'string','Cooler ON')
            
            %check and initalize temperature of chiller if it is on
            [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts] = GetTemperatureStatus();
            acooleractualtext.String = [num2str(SensorTemp) '°C'];
            acoolersettext.String = [num2str(TargetTemp) '°C'];
        else
            %chiller is off
            %do nothing
        end
        
        aloop_scan.Enable = 'on';
        
        if(astatus_selectbox.Value==1)
            %single scan mode
            a_kincyctime.Enable = 'off';
            a_numkinseries.Enable = 'off';
            [ret] = SetAcquisitionMode(1); % Set acquisition mode; 1 for single scan
            CheckWarning(ret);
            update_andor_output('Set up Single Scan')
            [ret] = SetExposureTime(str2num(a_integrationtime.String)); % Set exposure time in second
            CheckWarning(ret);
            update_andor_output(['Exposure Time: ' a_integrationtime.String ' s'])
        elseif(astatus_selectbox.Value==2)
            %kinetic series mode
            a_kincyctime.Enable = 'on';
            a_numkinseries.Enable = 'on';
            [ret] = SetAcquisitionMode(3); % Set acquisition mode; 3 for Kinetic Series
            CheckWarning(ret);
            update_andor_output('Set up Kinetic Series')
            
            [ret] = SetNumberKinetics(str2num(a_numkinseries.String));
            CheckWarning(ret);
            update_andor_output(['Length of Kinetic Series: ' a_numkinseries.String])
            
            [ret] = SetExposureTime(str2num(a_integrationtime.String)); % Set exposure time in second
            CheckWarning(ret);
            update_andor_output(['Exposure Time: ' a_integrationtime.String ' s'])
            
            [ret] = SetKineticCycleTime(str2num(a_kincyctime.String)); %set kinetic cycle time
            CheckWarning(ret);
            update_andor_output(['Cycle Time: ' a_kincyctime.String ' s'])
        end
        
        [ret] = SetReadMode(0); % Set read mode; 0 for FVP
        CheckWarning(ret);
        [ret] = SetTriggerMode(0); % Set internal trigger mode
        CheckWarning(ret);
        [ret,XPixels, YPixels] = GetDetector; % Get the CCD size
        CheckWarning(ret);
        
        [ret] = SetImage(1, 1, 1, XPixels, 1, YPixels); % Set the image size
        CheckWarning(ret);
        
        %initalize Shamrock Spectrometer
        wait_a_second(Andor_window_handle);
        [ret, nodevices] = ShamrockGetNumberDevices();
        if(ret==Shamrock.SHAMROCK_SUCCESS());
            %do nothing, already connected
        else
            [ret] = ShamrockInitialize('');
        end
        good_to_go(Andor_window_handle);
        [ret, nodevices] = ShamrockGetNumberDevices();
        %we are using device 0
        [ret,SN] = ShamrockGetSerialNumber(0);
        if(~strcmp(SN,'SR2116'))
            update_andor_output('Failed to initalize spectrometer')
            return
        else
            update_andor_output('Connected to Shamrock')
            center_wavelength_selectbox.Enable = 'on';
            grating_selectbox.Enable = 'on';
            aaqdata.Enable = 'on';
        end
        
        [ret,currentgrating] = ShamrockGetGrating(0);
        [ret,currentcenter] = ShamrockGetWavelength(0);
        [ret,Xcal] = ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        
        %and update the drop down to show correct center wavelength and grating
        center_wavelength_selectbox.Value = (round(currentcenter,-1)-350)/50;
        grating_selectbox.Value = currentgrating;
        
    end

    function update_andor_output(newstring)
        %add the string
        a_textreadout = find_ui_handle('a_textreadout',Andor_window_handle);
        a_textreadout.String{end+1} = newstring;
        %make sure box isn't over full
        a_textreadout.String = a_textreadout.String(max([1 end-9]):end);
    end

    function change_andor_exposure_time(source,eventdata)
        temp = getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output('Parameter not set!')
            beep;
            return
        end
        [ret,status] = AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output('Andor busy!')
            return
        end
        strstat = all(isstrprop(get(source,'string'),'digit')|isstrprop(get(source,'string'),'punct'));
        if(strstat)
            [ret] = SetExposureTime(str2num(source.String)); % Set exposure time in second
            CheckWarning(ret);
            update_andor_output(['Integration Time: ' source.String ' s'])
        else
            source.String = '15';
            beep
            update_andor_output('Numbers only in this field!')
        end
    end

    function change_andor_kinetic_time(source,eventdata)
        temp = getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output('Parameter not set!')
            beep;
            return
        end
        [ret,status] = AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output('Andor busy!')
            return
        end
        strstat = all(isstrprop(get(source,'string'),'digit')|isstrprop(get(source,'string'),'punct'))
        if(strstat)
            [ret] = SetKineticCycleTime(str2num(source.String)); %set kinetic cycle time
            CheckWarning(ret);
            update_andor_output(['Kinetic Cycle Time: ' source.String ' s']);
        else
            source.String = '30';
            beep
            update_andor_output('Numbers only in this field!')
        end
    end

    function change_andor_kinetic_length(source,eventdata)
        temp = getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output('Parameter not set!')
            beep;
            return
        end
        [ret,status] = AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output('Andor busy!')
            return
        end
        if(all(isstrprop(get(source,'string'),'digit')))
            [ret] = SetNumberKinetics(str2num(source.String));
            CheckWarning(ret);
            update_andor_output(['Length of Kinetic Series: ' source.String])
        else
            source.String = 5;
            beep
            update_andor_output('Numbers only in this field!')
        end
    end

    function change_andor_acquisition(source,eventdata)
        ax11 = find_ui_handle('ax11',Andor_window_handle);
        a_kincyctime = find_ui_handle('a_kincyctime',Andor_window_handle);
        a_numkinseries = find_ui_handle('a_numkinseries',Andor_window_handle);
        temp = getappdata(main);
        if(~temp.AndorFlag)
            update_andor_output('Connect to Andor First!')
            beep;
            return
        end
        [ret,status] = AndorGetStatus;
        if(status~=atmcd.DRV_IDLE)
            beep;warning('Parameter not set')
            update_andor_output('Andor busy!')
            return
        end
        if(get(source,'value')==1)
            [ret] = SetAcquisitionMode(1); % Set acquisition mode; 1 for single scan
            CheckWarning(ret);
            a_kincyctime.Enable = 'off';
            a_numkinseries.Enable = 'off';
            update_andor_output('Set to single scan mode')
        elseif(get(source,'value')==2)
            a_kincyctime.Enable = 'on';
            a_numkinseries.Enable = 'on';
            [ret] = SetAcquisitionMode(3); % Set acquisition mode; 3 for Kinetic Series
            CheckWarning(ret);
            update_andor_output('Set to kinetic series mode')
        end
        cla(ax11)
    end

    function andor_disconnect(source,eventdata)
        %stop any ongoing acquisitions
        [ret] = AbortAcquisition;
        CheckWarning(ret);
        %turn off the cooler
        [ret] = CoolerOFF;
        CheckWarning(ret);
        %close the shutter
        [ret] = SetShutter(1, 2, 1, 1);
        CheckWarning(ret);
        %shut it down
        [ret] = AndorShutDown;
        CheckWarning(ret);
        setappdata(main,'AndorFlag',0)
        update_andor_output('Disconnected from Andor')
        ShamrockClose();
        update_andor_output('Disconnected from Shamrock')
        aloop_scan = find_ui_handle('aloop_scan',Andor_window_handle);
        aaqdata = find_ui_handle('aaqdata',Andor_window_handle);
        center_wavelength_selectbox = find_ui_handle('center_wavelength_selectbox',...
            Andor_window_handle);
        grating_selectbox = find_ui_handle('grating_selectbox',...
            Andor_window_handle);
        center_wavelength_selectbox.Enable = 'off';
        grating_selectbox.Enable = 'off';
        aloop_scan.Enable = 'on';
        aaqdata.Enable = 'off';
    end

    function andor_abort_sub(source,eventdata)
        [ret] = AbortAcquisition;
        CheckWarning(ret);
        if(ret==20002)
            update_andor_output('Acquisition Aborted')
        else
            update_andor_output('Error! Acquisition not aborted!')
        end
    end

    function andor_chiller_power(source,eventdata)
        %when turning on
        if(get(source,'value'))
            [ret] = CoolerON();
            CheckError(ret);
            source.String = 'Cooler On';
            %send setpoint temperature to chiller
            acoolerset = find_ui_handle('acoolerset',Andor_window_handle);
            [ret] = SetTemperature(str2num(acoolerset.String));
            CheckError(ret);
            %check and initalize temperature of chiller if it is on
            [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts] = GetTemperatureStatus();
            acooleractualtext = find_ui_handle('acooleractualtext',...
                Andor_window_handle);
            acoolersettext = find_ui_handle('acoolersettext',...
                Andor_window_handle);
            acooleractualtext.String = [num2str(SensorTemp,'%3.1f') '°C'];
            acoolersettext.String = [num2str(TargetTemp,'%3.f') '°C'];
        else
            [ret] = CoolerOFF();
            CheckError(ret);
            source.String = 'Cooler Off';
        end
    end

    function andor_set_chiller_temp(source,eventdata)
        acoolersettext = find_ui_handle('acoolersettext',...
            Andor_window_handle);
        T = str2num(source.String);
        %force T to reasonable range
        if(T<-60)
            T = -60;
        elseif(T>25)
            T = 25;
        elseif(isempty(T))
            update_andor_output('Invalid temperature');
            source.String = '-60';
            return
        end
        acoolersettext.String = [num2str(T,'%3.f') '°C'];
        [ret] = SetTemperature(T);
        CheckError(ret)
    end

    function update_Andor_values()
        [ret, SensorTemp, TargetTemp, AmbientTemp, CoolerVolts] = GetTemperatureStatus();
        acooleractualtext = find_ui_handle('acooleractualtext',...
            Andor_window_handle);
        acoolersettext = find_ui_handle('acoolersettext',Andor_window_handle);
        acooleractualtext.String = [num2str(SensorTemp,'%3.1f') '°C'];
        acoolersettext.String = [num2str(TargetTemp,'%3.f') '°C'];
    end

    function change_andor_wavelength(source,eventdata)
        target = source.String{source.Value};
        [ret] = ShamrockSetWavelength(0,str2num(target(1:3)));
        [ret,currentgrating] = ShamrockGetGrating(0);
        [ret,currentcenter] = ShamrockGetWavelength(0);
        [ret,Xcal] = ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        update_andor_output(['Center wavelength now ' target(1:3) ' nm'])
    end

    function change_andor_grating(source,eventdata)
        target = source.Value;
        [ret] = ShamrockSetGrating(0,target);
        [ret,currentgrating] = ShamrockGetGrating(0);
        [ret,currentcenter] = ShamrockGetWavelength(0);
        [ret,Xcal] = ShamrockGetCalibration(0,2000);
        %save number of XPixels for later
        setappdata(main,'ShamrockGrating',currentgrating)
        setappdata(main,'ShamrockWavelength',currentcenter)
        setappdata(main,'ShamrockXCal',Xcal);
        update_andor_output(['Changed to grating number ' num2str(target)])
    end

    function andor_aqdata(source,eventdata)
        wasrunning = strcmp(fasttimer.running,'on');
        stop(fasttimer)
        stop(errorcatchtimer)
        pause(0.25)
        astatus_selectbox = find_ui_handle('astatus_selectbox',...
            Andor_window_handle);
        [ret] = SetShutter(1, 0, 1, 1); % auto Shutter
        CheckWarning(ret);
        
        %retrieve Xpixel data
        temp = getappdata(main);
        XPixels = 2000;
        
        temp.AndorImage_startpointer = max([size(temp.AndorImage,2) 1]);
        setappdata(main,'AndorImage_startpointer',temp.AndorImage_startpointer);
        
        %check to ensure the number of existing timestamps and datapoints
        %matches
        if(size(temp.AndorImage,2)<length(temp.AndorTimestamp))
            %trim the number of AndorTimestamps
            update_andor_output('Warning: mismatch in existing')
            update_andor_output('timestamps and spectra!')
            update_andor_output('Trimming timestamps.')
            temp.AndorTimestamp(size(temp.AndorImage,2)+1:end) = [];
            setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
        elseif(size(temp.AndorImage,2)>length(temp.AndorTimestamp))
            %insert NaNs into the timestamps to preserve data
            update_andor_output('Warning: mismatch in existing')
            update_andor_output('timestamps and spectra!')
            update_andor_output('NaN-Padding timestamps.')
            if(~isempty(temp.AndorTimestamp))
                temp.AndorTimestamp(end:size(temp.AndorImage,2)) = NaN;
            else
                temp.AndorTimestamp = NaN;
            end
            setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
        end
        
        [ret] = StartAcquisition();
        CheckWarning(ret);
        update_andor_output('Starting Acquisition')
        
        [ret,exposed_time,~,cycle_time] = GetAcquisitionTimings;
        if(astatus_selectbox.Value==2) %kinetic scan
            a_numkinseries = find_ui_handle('a_numkinseries',...
                Andor_window_handle);
            number_exposure = str2num(a_numkinseries.String);
        else
            number_exposure = 1;
        end
        currenttime = clock;
        %generate a series of timestamps spaced by cycle_time
        AndorTimestamp = datenum(currenttime(1),currenttime(2),currenttime(3),currenttime(4),currenttime(5),(currenttime(6)+exposed_time/2):cycle_time:(currenttime(6)+cycle_time.*number_exposure));
        AndorCalPoly = repmat(polyfit(1:2000,temp.ShamrockXCal',2),length(AndorTimestamp),1);
        
        if(~isempty(temp.AndorTimestamp))
            temp.AndorTimestamp = [temp.AndorTimestamp AndorTimestamp];
        else
            temp.AndorTimestamp = AndorTimestamp;
        end
        
        if(~isempty(temp.AndorCalPoly))
            temp.AndorTimestamp = [temp.AndorCalPoly AndorCalPoly];
        else
            temp.AndorCalPoly = AndorCalPoly;
        end
        setappdata(main,'AndorTimestamp',temp.AndorTimestamp)
        if(wasrunning)
            start(fasttimer)
        end
        start(errorcatchtimer)
    end

    function get_andor_data(source,eventdata)
        temp = getappdata(main);
        astatus_selectbox = find_ui_handle('astatus_selectbox',...
            Andor_window_handle);
        
        %get the number of available frames, if any
        [ret,firstimage_ind,lastimage_ind] = GetNumberNewImages;
        %get newest image when "SUCCESS" is returned
        if(astatus_selectbox.Value==1&&ret==atmcd.DRV_SUCCESS)
            %single scans
            [ret,AndorImage] = GetOldestImage(2000);
            %convert to unsigned 16 bit image to save space
            AndorImage = uint16(AndorImage);
            if(ret==20024)
                %no new data
                return
            end
            aloop_scan = find_ui_handle('aloop_scan',Andor_window_handle);
            if(aloop_scan.Value)
                %if loop scan is checked, restart the acq.
                andor_aqdata(source,eventdata);
            else
                [ret] = SetShutter(1, 2, 1, 1); % close Shutter
                CheckWarning(ret);
                update_andor_output('Aquisition complete')
            end
            %                 %and save data
            if(isempty(temp.AndorImage))
                temp.AndorImage = AndorImage;
            else
                temp.AndorImage(:,end+1) = AndorImage;
            end
            if(~isa(temp.AndorImage,'uint16'))
                temp.AndorImage = uint16(temp.AndorImage);
            end
            setappdata(main,'AndorImage',temp.AndorImage);
        elseif(astatus_selectbox.Value==2&&ret==atmcd.DRV_SUCCESS)
            if(~isa(temp.AndorImage,'uint16'))
                temp.AndorImage = uint16(temp.AndorImage);
            end
            for i = firstimage_ind:lastimage_ind
                [ret,tempimage] = GetOldestImage(2000);
                temp.AndorImage(:,temp.AndorImage_startpointer+i) = uint16(tempimage);
                CheckWarning(ret);
                update_andor_output(['Got frame number ' num2str(i)])
                setappdata(main,'AndorImage',temp.AndorImage)
            end
            [ret,status] = AndorGetStatus();
            if(status==atmcd.DRV_IDLE)
                %if the device is idle, close the shutter
                [ret] = SetShutter(1, 2, 1, 1); % close Shutter
                CheckWarning(ret);
                update_andor_output(['Aquisition complete'])
            end
        end
    end

    function update_andor_plot_1D(axishandle)
        temp = getappdata(main);
        if(isempty(temp.AndorImage_startpointer))
            %do nothing
            return
        end
        if(temp.AndorImage_startpointer>=size(temp.AndorImage,2))
            %no new data to plot
            if(temp.AndorImage_startpointer~=1)
                return
            end
        end
        cla(axishandle)
        AndorImage = temp.AndorImage(:,end);
        set(axishandle, 'XTickMode', 'auto', 'XTickLabelMode', 'auto')
        h = plot(axishandle,temp.ShamrockXCal,AndorImage);
        new_ylimits = prctile(single(AndorImage),[1 99]);
        new_ylimits(1) = new_ylimits(1)-50;
        new_ylimits(2) = new_ylimits(2)+50;
        set(axishandle,'ylim',new_ylimits);
        xlabel(axishandle,'Wavelength (nm)');
        ylabel(axishandle,'Intensity (s^{-1})');
        xlim(axishandle,[temp.ShamrockXCal(1) temp.ShamrockXCal(end)])
        dim = [.6 .6 .3 .3];
        str = ['Time: ' datestr(now)];
        xtextloc = temp.ShamrockXCal(end)-(temp.ShamrockXCal(end)-temp.ShamrockXCal(1))/2;
        ytextloc = (new_ylimits(2)*4+new_ylimits(1))/5;
        text(axishandle,double(xtextloc),double(ytextloc),str)
    end

    function update_andor_plot_2D()
        two_d_plottime = tic;
        ax11 = find_ui_handle('ax11',Andor_window_handle);
        temp = getappdata(main);
        start_ind = max([temp.AndorImage_startpointer+1 1]);
        if(isempty(temp.AndorImage))
            return
        end
        X = temp.AndorTimestamp(start_ind:size(temp.AndorImage,2));
        Y = temp.ShamrockXCal;
        Image_w_gaps = double(temp.AndorImage(:,start_ind:end));
        if(size(Image_w_gaps,2)<2)
            return
        end
        
        spacing = max([1 floor(size(Image_w_gaps,2)./500)]);
        Image_w_gaps = Image_w_gaps(:,1:spacing:end);
        X = X(1:spacing:end);
        
        %find gaps
        dX = diff(X);
        gaps = find(dX>(spacing*5/60/24)); %need to include factor of spacing to keep it from rejecting everything
        for i = fliplr(gaps)
            X = [X(1:i) NaN X(i+1:end)];
            Image_w_gaps = [Image_w_gaps(:,1:i) ones(size(Y')).*1300 Image_w_gaps(:,i+1:end)];
        end
        
        if(0)
            fitX = (1:2000)';
            %this is some sort of filter but TBH I have no idea how it works
            %anymore
            %TODO: save the fitted data for subtraction? Save subtracted data
            %and append it?
            g = fittype('a1*exp(-(b1*(x-c1))^2)+a2*exp(-(b2*(x-c2))^2)+d');
            fo = fitoptions(g);
            fo.Lower = [100 100 0 0 600 600 1000];
            fo.Upper = [500 500 1 1 1400 1400 1400];
            %I think this might subtract off the constant background offset?
            fo.StartPoint = [175 175 0.005 0.005 800 800 1250];
            comp = nanmean(Image_w_gaps,2);
            fit_to_1D = fit(fitX,comp,g,fo);
            fitted = double(fit_to_1D.a1*exp(-(fit_to_1D.b1*(fitX-fit_to_1D.c1)).^2)+...
                fit_to_1D.a2*exp(-(fit_to_1D.b2*(fitX-fit_to_1D.c2)).^2)+...
                fit_to_1D.d);
            
            plotdata = (Image_w_gaps)-repmat(fitted,1,size(Image_w_gaps,2));
        else
            plotdata = (Image_w_gaps);
        end
        h = pcolor(ax11,X,Y,plotdata);
        set(h,'linestyle','none');
        new_climits = [max([ min(min(prctile(single(plotdata),[10 95]))) 1000]) ...
            min([max(max(prctile(single(plotdata),[10 95]))) 1500])];
        
        set(ax11,'CLimMode','manual','CLim',new_climits)
        datetick(ax11,'x','HH:MM')
        xlabel(ax11,'Time (HH:MM)')
        ylabel(ax11,'Wavelength (nm)')
        toc(two_d_plottime);
    end

    function Andor_Realtime(source,eventdata)
        runloop = source.Value;
        temp = getappdata(main);
        astatus_selectbox = find_ui_handle('astatus_selectbox',...
           Andor_window_handle);
        a_kincyctime = find_ui_handle('a_kincyctime',Andor_window_handle);
        a_numkinseries = find_ui_handle('a_numkinseries',Andor_window_handle);
        a_integrationtime = find_ui_handle('a_integrationtime',...
           Andor_window_handle);
        aaqdata = find_ui_handle('aaqdata',Andor_window_handle);
        center_wavelength_selectbox = find_ui_handle('center_wavelength_selectbox',...
           Andor_window_handle);
        grating_selectbox = find_ui_handle('grating_selectbox',...
           Andor_window_handle);
        ax11 = find_ui_handle('ax11',Andor_window_handle);
        center_wavelength_selectbox.Enable = 'off';
        grating_selectbox.Enable = 'off';
        a_kincyctime.Enable = 'off';
        a_numkinseries.Enable = 'off';
        a_integrationtime.Enable = 'off';
        astatus_selectbox.Enable = 'off';
        aaqdata.Enable = 'off';

        if(runloop)
          %ensure auto shutter
          [ret] = SetShutter(1, 0, 1, 1); % Auto Shutter
        end

        while(runloop)
            disp([datestr(now) ' Andor Realtime'])
            pause(0.01)

            [ret] = StartAcquisition();
            CheckWarning(ret);

            [ret,gstatus] = AndorGetStatus;
            CheckWarning(ret);
            while(gstatus ~= atmcd.DRV_IDLE)
                pause(0.25);
                disp('Acquiring');
                [ret,gstatus] = AndorGetStatus;
                CheckWarning(ret);
            end

            [ret, imageData] = GetMostRecentImage(2000);
            CheckWarning(ret);

            plot(ax11,temp.ShamrockXCal,imageData)
            new_ylimits = prctile(single(imageData),[10 90]);
            new_ylimits(1) = new_ylimits(1)-10;
            new_ylimits(2) = new_ylimits(2)+20;
            set(ax11,'ylim',new_ylimits);

            aloop_scan = find_ui_handle('aloop_scan',Andor_window_handle);
            runloop = aloop_scan.Value;
        end

        a_kincyctime.Enable = 'on';
        a_numkinseries.Enable = 'on';
        a_integrationtime.Enable = 'on';
        astatus_selectbox.Enable = 'on';
        if(temp.AndorFlag)
            center_wavelength_selectbox = find_ui_handle('center_wavelength_selectbox',...
                Andor_window_handle);
            grating_selectbox = find_ui_handle('grating_selectbox',...
                Andor_window_handle);
            aaqdata = find_ui_handle('aaqdata',Andor_window_handle);
            center_wavelength_selectbox.Enable = 'on';
            grating_selectbox.Enable = 'on';
            aaqdata.Enable = 'on';
        end
        
    end

%% functions that actually do stuff for the hygrometer window

    function hygrometer_comms(source,eventdata)
        
        hygrometer_selectbox = find_ui_handle('hygrometer_selectbox',...
            hygrometer_window_handle);
        hygrometer_openclose = find_ui_handle('hygrometer_openclose',...
            hygrometer_window_handle);
        if(source.Value)
            %open the connection
            %determine which port is selected
            portID = hygrometer_selectbox.String{hygrometer_selectbox.Value};
            obj3 = instrfind('Type', 'serial', 'Port', portID, 'Tag', '');
            if(isempty(obj3))
                obj3 = serial(portID);
            else
                fclose(obj3);
                obj3 = obj3(1);
            end
            
            obj3.Terminator = {'CR/LF','CR'};
            obj3.BaudRate = 38400;
            obj3.Timeout = 1;
            
            fopen(obj3);
            
            %ensure that data is written upon query only
            fprintf(obj3,'$SERIALMODEQUERY ')
            b = fscanf(obj3);
            c = fscanf(obj3);
            d = fscanf(obj3);
            
            setappdata(main,'Hygrometer_comms',obj3)
            
            hygrometer_selectbox.Enable = 'off';
            hygrometer_openclose.String = 'Port Open';
        else
            %close the connection
            temp = getappdata(main);
            if(isfield(temp,'Hygrometer_comms'))
                %close the comm and delete it from memory
                fclose(temp.Hygrometer_comms);
                rmappdata(main,'Hygrometer_comms');
            else
                %do nothing
            end
            hygrometer_selectbox.Enable = 'on';
            hygrometer_openclose.String = 'Port Closed';
        end
    end

    function force_hygrometer_normal()
        temp = getappdata(main);

        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$ACTION 0 ')
        for i = 1:2
            a = fscanf(temp.Hygrometer_comms);
        end
    end

    function update_hygrometer_data()
        
        temp = getappdata(main);
        
        flushinput(temp.Hygrometer_comms)
        fprintf(temp.Hygrometer_comms,'$GETDATA 0')
        for i = 1:3
            a = fscanf(temp.Hygrometer_comms);
        end
        
        eqinx = strfind(a,'=');
        Td = str2num(a(eqinx+1:end));
        
        % calculate theoretical dewpoint if available
        hum_table = find_ui_handle('hum_table',MKS_window_handle);
        dwpt_thy = NaN; %set a default value
        if(hum_table.Data(1,2)~=-999)
            % assuming RT = 19 deg C
            julabo_set_t = find_ui_handle('Julabo_set_T',MKS_window_handle);
            julabo_set_t_num = str2num(julabo_set_t.String)
            if(isa(julabo_set_t_num,'numeric'))
                Bath_T = julabo_set_t_num
            else
                Bath_T = 19;
            end
            RH_thy = hum_table.Data(1,3)/100;
            %calculate the theoretical dewpoint
            Trap_saturation = water_vapor_pressure(hum_table.Data(1,2)+273.15);
            dwpt_thy = (water_dew_pt(Trap_saturation*RH_thy)-273.15);
        end
        
        if(isempty(Td))
            Td = NaN;
        end
        
        if(~isreal(dwpt_thy)|RH_thy==0)
            dwpt_thy = NaN;
        end
        
        temp.hygrometer_data(end+1,:) = [now Td dwpt_thy];
        setappdata(main,'hygrometer_data',temp.hygrometer_data)
        update_hygrometer_plot()
    end

    function update_hygrometer_plot()
        temp = getappdata(main);
        ax20 = find_ui_handle('ax20',hygrometer_window_handle);
        a_textreadout = find_ui_handle('a_textreadout',Andor_window_handle);
        
        if(size(temp.hygrometer_data,1)>=2)
            plot(ax20,temp.hygrometer_data(:,1),temp.hygrometer_data(:,2),'.',...
                temp.hygrometer_data(:,1),temp.hygrometer_data(:,3),'o')
            
            ylabel(ax20,'Td ^\circ C')
            xlabel(ax20,'Time DD HH')
            datetick(ax20,'x','DD HH')
        end
        
        a_textreadout.String = [datestr(temp.hygrometer_data(end,1))...
            ' Hygrometer: ' num2str(temp.hygrometer_data(end,2)) ...
            '°C; Thy: ' num2str(temp.hygrometer_data(end,3),'%.2f') '°C'];
    end
end
