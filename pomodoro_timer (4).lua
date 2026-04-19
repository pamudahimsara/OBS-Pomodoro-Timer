obs = obslua

-- ═══════════════════════════════════════════════════════════
--   POMODORO TIMER FOR OBS — FINAL v5
--   Features:
--     - Auto subject cycling + manual prev/next subject
--     - Per-subject time tracking + %
--     - ASCII progress bars (session + overall)
--     - Crash resume (hours + minutes separately)
--     - Auto scene switching (Study / Break scenes)
--     - CSV session log
--     - Selectable alarm source
--     - Skip phase button
--     - Custom subject list (editable in panel)
--     - PAUSED display on screen
--     - End-of-session warning prefix
--     - Manual break (Start / +5min / End Break)
--     - Custom break label
--     - Separate manual break duration
--     - Smooth 50ms fade animation
-- ═══════════════════════════════════════════════════════════

-- ── SETTINGS ────────────────────────────────────────────────
study_minutes        = 50
break_minutes        = 10
manual_break_minutes = 10
total_hours          = 15
auto_cycle           = true

subjects              = {"Physics", "Chemistry", "Applied Maths", "Pure Maths"}
custom_subjects_str   = "Physics,Chemistry,Applied Maths,Pure Maths"
current_subject_index = 1

resume_hours   = 0
resume_minutes = 0      -- NEW: resume minutes (on top of hours)
resume_sessions = 0

study_scene_name  = ""
break_scene_name  = ""
alarm_source_name = ""
log_file_path     = ""
warning_secs      = 60
custom_break_name = "BREAK"

-- ── STATE ────────────────────────────────────────────────────
session_count       = 1
is_study            = true
in_manual_break     = false
time_left           = study_minutes * 60
total_seconds       = total_hours * 3600
total_study_seconds = 0
session_study_secs  = 0

subject_seconds = {}
for i = 1, #subjects do subject_seconds[i] = 0 end

source_name = ""
source      = nil

timer_running = false
timer_paused  = false

show_subject     = true
show_total       = true
show_subject_pct = true
enable_blink     = true
enable_fade      = false

blink    = true
fade     = 1.0
fade_dir = -1

-- ── SOUND ────────────────────────────────────────────────────
function play_sound()
    if alarm_source_name == "" then return end
    local snd = obs.obs_get_source_by_name(alarm_source_name)
    if snd == nil then return end
    obs.obs_source_media_restart(snd)
    obs.obs_source_release(snd)
end

-- ── SCENE SWITCHING ──────────────────────────────────────────
function switch_to_scene(scene_name)
    if scene_name == nil or scene_name == "" then return end
    local sc = obs.obs_get_source_by_name(scene_name)
    if sc ~= nil then
        obs.obs_frontend_set_current_scene(sc)
        obs.obs_source_release(sc)
    end
end

-- ── SESSION LOG ──────────────────────────────────────────────
function log_session(subj, duration_secs, phase)
    if log_file_path == "" then return end
    local f = io.open(log_file_path, "a")
    if f == nil then return end
    local sz = f:seek("end")
    if sz == 0 then f:write("date,time,phase,subject,duration_minutes\n") end
    local t = os.date("*t")
    f:write(string.format("%04d-%02d-%02d,%02d:%02d:%02d,%s,%s,%.1f\n",
        t.year, t.month, t.day, t.hour, t.min, t.sec,
        phase, subj, duration_secs / 60))
    f:close()
end

-- ── SUBJECT HELPERS ──────────────────────────────────────────
function parse_subjects(str)
    local result = {}
    for part in str:gmatch("([^,]+)") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then table.insert(result, trimmed) end
    end
    if #result == 0 then result = {"Study"} end
    return result
end

function current_subject()
    return subjects[current_subject_index] or "—"
end

function advance_subject()
    if auto_cycle then
        current_subject_index = (current_subject_index % #subjects) + 1
    end
end

function next_subject(props, prop)
    current_subject_index = (current_subject_index % #subjects) + 1
    subject_seconds[current_subject_index] = subject_seconds[current_subject_index] or 0
    update_text()
end

function prev_subject(props, prop)
    current_subject_index = ((current_subject_index - 2) % #subjects) + 1
    subject_seconds[current_subject_index] = subject_seconds[current_subject_index] or 0
    update_text()
end

-- ── FORMATTING ───────────────────────────────────────────────
function format_hm(sec)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m)
    else return string.format("%dm", m) end
end

function make_bar(fraction, width)
    width = width or 18
    local filled = math.max(0, math.min(width, math.floor(fraction * width + 0.5)))
    return string.rep("█", filled) .. string.rep("░", width - filled)
end

-- ── TEXT UPDATE ──────────────────────────────────────────────
function update_text()
    if source == nil then return end

    if timer_paused then
        local cfg = obs.obs_data_create()
        obs.obs_data_set_string(cfg, "text",
            "[ PAUSED ]\n" ..
            string.format("%02d:%02d left", math.floor(time_left/60), time_left%60) ..
            "\n" .. (is_study and "STUDY" or custom_break_name) ..
            "\nSESSION " .. session_count)
        obs.obs_source_update(source, cfg)
        obs.obs_data_release(cfg)
        return
    end

    local colon = ":"
    if enable_blink then colon = blink and ":" or " " end

    local m = math.floor(time_left / 60)
    local s = time_left % 60

    local warn = ""
    if warning_secs > 0 and time_left <= warning_secs and time_left > 0
       and timer_running and not in_manual_break then
        warn = "! "
    end

    local time_str = warn .. string.format("%02d%s%02d", m, colon, s)

    local session_total
    if is_study then
        session_total = study_minutes * 60
    elseif in_manual_break then
        session_total = manual_break_minutes * 60
    else
        session_total = break_minutes * 60
    end
    local elapsed = math.max(0, session_total - time_left)
    local bar = make_bar(elapsed / session_total, 18)

    local overall_pct = math.min(100, math.floor((total_study_seconds / total_seconds) * 100))
    local total_sessions = math.ceil(total_seconds / (study_minutes * 60))
    local mode = is_study and "STUDY" or (in_manual_break and ("[" .. custom_break_name .. "]") or custom_break_name)

    local lines = {}
    table.insert(lines, mode)
    table.insert(lines, time_str)
    table.insert(lines, bar)

    if show_subject and is_study then
        local subj_line = current_subject()
        if show_subject_pct and total_study_seconds > 0 then
            local pct = math.floor(
                (subject_seconds[current_subject_index] / total_study_seconds) * 100)
            subj_line = subj_line .. string.format(" [%d%%]", pct)
        end
        table.insert(lines, subj_line)
    end

    table.insert(lines, string.format("SESSION %d / %d", session_count, total_sessions))

    if show_total then
        table.insert(lines, string.format("TOTAL %s (%d%%)",
            format_hm(total_study_seconds), overall_pct))
        table.insert(lines, make_bar(total_study_seconds / total_seconds, 18))
    end

    local cfg = obs.obs_data_create()
    obs.obs_data_set_string(cfg, "text", table.concat(lines, "\n"))
    obs.obs_source_update(source, cfg)
    obs.obs_data_release(cfg)
end

-- ── ANIMATION (50ms smooth) ──────────────────────────────────
function animate()
    if source == nil or not enable_fade then return end
    fade = fade + (fade_dir * 0.03)
    if fade >= 1.0 then fade = 1.0; fade_dir = -1
    elseif fade <= 0.5 then fade = 0.5; fade_dir = 1 end
    local cfg = obs.obs_source_get_settings(source)
    obs.obs_data_set_int(cfg, "opacity", math.floor(fade * 100))
    obs.obs_source_update(source, cfg)
    obs.obs_data_release(cfg)
end

-- ── PHASE TRANSITION ─────────────────────────────────────────
function do_phase_transition()
    play_sound()
    if is_study then
        log_session(current_subject(), session_study_secs, "study")
        switch_to_scene(break_scene_name)
        is_study           = false
        in_manual_break    = false
        time_left          = break_minutes * 60
        session_study_secs = 0
    else
        log_session(custom_break_name, break_minutes * 60, "break")
        session_count = session_count + 1
        advance_subject()
        switch_to_scene(study_scene_name)
        is_study        = true
        in_manual_break = false
        time_left       = study_minutes * 60
    end
    update_text()
end

-- ── SKIP ─────────────────────────────────────────────────────
function skip_phase(props, prop)
    if not timer_running then return end
    do_phase_transition()
end

-- ── MANUAL BREAK ─────────────────────────────────────────────
function start_break(props, prop)
    if not timer_running then return end
    is_study        = false
    in_manual_break = true
    time_left       = manual_break_minutes * 60
    switch_to_scene(break_scene_name)
    update_text()
end

function extend_break(props, prop)
    if not timer_running then return end
    if not is_study then
        time_left = time_left + 300
        update_text()
    end
end

function end_break(props, prop)
    if not timer_running then return end
    in_manual_break = false
    is_study        = true
    time_left       = study_minutes * 60
    switch_to_scene(study_scene_name)
    update_text()
end

-- ── TICK ─────────────────────────────────────────────────────
function tick()
    if not timer_running or timer_paused then return end

    blink = not blink

    if time_left > 0 then
        time_left = time_left - 1
        if is_study then
            total_study_seconds = total_study_seconds + 1
            session_study_secs  = session_study_secs + 1
            subject_seconds[current_subject_index] =
                subject_seconds[current_subject_index] + 1
        end
        update_text()
        return
    end

    -- manual break expired: alarm + hold, don't auto-advance
    if in_manual_break then
        play_sound()
        update_text()
        return
    end

    do_phase_transition()
end

-- ── TIMER CONTROL ────────────────────────────────────────────
function reset_state()
    session_count       = 1 + resume_sessions
    is_study            = true
    in_manual_break     = false
    time_left           = study_minutes * 60
    -- resume in hours + minutes combined
    total_study_seconds = (resume_hours * 3600) + (resume_minutes * 60)
    session_study_secs  = 0
    blink               = true
    fade                = 1.0
    subject_seconds     = {}
    for i = 1, #subjects do subject_seconds[i] = 0 end
end

function start_timer(props, prop)
    if timer_running and not timer_paused then return end
    if not timer_running then
        reset_state()
        obs.timer_remove(tick)
        obs.timer_remove(animate)
        obs.timer_add(tick,    1000)
        obs.timer_add(animate,   50)
        timer_running = true
        switch_to_scene(study_scene_name)
    end
    timer_paused = false
    update_text()
end

function pause_timer(props, prop)
    if timer_running then timer_paused = not timer_paused end
    update_text()
end

function stop_timer(props, prop)
    obs.timer_remove(tick)
    obs.timer_remove(animate)
    timer_running   = false
    timer_paused    = false
    in_manual_break = false
    if source ~= nil and enable_fade then
        local cfg = obs.obs_source_get_settings(source)
        obs.obs_data_set_int(cfg, "opacity", 100)
        obs.obs_source_update(source, cfg)
        obs.obs_data_release(cfg)
    end
    reset_state()
    update_text()
end

-- ── SCRIPT LIFECYCLE ─────────────────────────────────────────
function script_description()
    return [[<h2>Pomodoro Timer — Final v5</h2>
<b>Setup:</b>
<ol>
<li>Add a <i>Text (GDI+)</i> source → select below.</li>
<li>Add a <i>Media Source</i> for your alarm → select below.</li>
<li>Name your Study/Break scenes below (optional).</li>
<li>Set a CSV log path like <tt>C:\study_log.csv</tt> (optional).</li>
</ol>]]
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings,    "study_minutes",        50)
    obs.obs_data_set_default_int(settings,    "break_minutes",        10)
    obs.obs_data_set_default_int(settings,    "manual_break_minutes", 10)
    obs.obs_data_set_default_int(settings,    "total_hours",          15)
    obs.obs_data_set_default_int(settings,    "resume_hours",          0)
    obs.obs_data_set_default_int(settings,    "resume_minutes",        0)
    obs.obs_data_set_default_int(settings,    "resume_sessions",       0)
    obs.obs_data_set_default_int(settings,    "warning_secs",         60)
    obs.obs_data_set_default_bool(settings,   "auto_cycle",         true)
    obs.obs_data_set_default_bool(settings,   "show_subject",       true)
    obs.obs_data_set_default_bool(settings,   "show_total",         true)
    obs.obs_data_set_default_bool(settings,   "show_subject_pct",   true)
    obs.obs_data_set_default_bool(settings,   "enable_blink",       true)
    obs.obs_data_set_default_bool(settings,   "enable_fade",       false)
    obs.obs_data_set_default_string(settings, "custom_subjects",
        "Physics,Chemistry,Applied Maths,Pure Maths")
    obs.obs_data_set_default_string(settings, "custom_break_name",  "BREAK")
    obs.obs_data_set_default_string(settings, "alarm_source_name",  "")
    obs.obs_data_set_default_string(settings, "log_file_path",      "")
    obs.obs_data_set_default_string(settings, "study_scene_name",   "")
    obs.obs_data_set_default_string(settings, "break_scene_name",   "")
end

function script_properties()
    local props = obs.obs_properties_create()

    -- text source
    local src_list = obs.obs_properties_add_list(props, "source_name", "Text Source",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(src_list, "-- select --", "")
    local srcs = obs.obs_enum_sources()
    if srcs then
        for _, s in ipairs(srcs) do
            local n = obs.obs_source_get_name(s)
            obs.obs_property_list_add_string(src_list, n, n)
        end
        obs.source_list_release(srcs)
    end

    -- alarm source
    local alarm_list = obs.obs_properties_add_list(props, "alarm_source_name",
        "Alarm Sound Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(alarm_list, "-- select --", "")
    local srcs2 = obs.obs_enum_sources()
    if srcs2 then
        for _, s in ipairs(srcs2) do
            local n = obs.obs_source_get_name(s)
            obs.obs_property_list_add_string(alarm_list, n, n)
        end
        obs.source_list_release(srcs2)
    end

    -- timing
    obs.obs_properties_add_int(props, "study_minutes",        "Study Minutes",         1, 180, 1)
    obs.obs_properties_add_int(props, "break_minutes",        "Auto Break Minutes",    1,  60, 1)
    obs.obs_properties_add_int(props, "manual_break_minutes", "Manual Break Minutes",  1, 120, 1)
    obs.obs_properties_add_int(props, "total_hours",          "Goal Hours",            1,  48, 1)
    obs.obs_properties_add_int(props, "warning_secs",         "End Warning (seconds)", 0, 300,  5)

    -- resume (hours + minutes separately)
    obs.obs_properties_add_int(props, "resume_hours",    "Resume: Hours Done",    0,  48,  1)
    obs.obs_properties_add_int(props, "resume_minutes",  "Resume: Minutes Done",  0,  59,  1)
    obs.obs_properties_add_int(props, "resume_sessions", "Resume: Sessions Done", 0, 200,  1)

    -- subjects
    obs.obs_properties_add_text(props, "custom_subjects",
        "Subjects (comma-separated)", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_bool(props, "auto_cycle", "Auto-cycle subjects each session")

    -- break label
    obs.obs_properties_add_text(props, "custom_break_name",
        "Break Label (shown on screen)", obs.OBS_TEXT_DEFAULT)

    -- scene switching
    obs.obs_properties_add_text(props, "study_scene_name", "Study Scene Name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "break_scene_name", "Break Scene Name", obs.OBS_TEXT_DEFAULT)

    -- log
    obs.obs_properties_add_text(props, "log_file_path",
        "CSV Log File Path", obs.OBS_TEXT_DEFAULT)

    -- display toggles
    obs.obs_properties_add_bool(props, "show_subject",     "Show Current Subject")
    obs.obs_properties_add_bool(props, "show_subject_pct", "Show Subject % of Study Time")
    obs.obs_properties_add_bool(props, "show_total",       "Show Total Study Time")
    obs.obs_properties_add_bool(props, "enable_blink",     "Blink Colon")
    obs.obs_properties_add_bool(props, "enable_fade",      "Pulse Opacity Animation")

    -- main controls
    obs.obs_properties_add_button(props, "btn_start", "Start / Resume", start_timer)
    obs.obs_properties_add_button(props, "btn_pause", "Pause / Unpause", pause_timer)
    obs.obs_properties_add_button(props, "btn_skip",  "Skip Phase",     skip_phase)
    obs.obs_properties_add_button(props, "btn_stop",  "Stop & Reset",   stop_timer)

    -- manual break
    obs.obs_properties_add_button(props, "btn_break_start",  "Start Break", start_break)
    obs.obs_properties_add_button(props, "btn_break_extend", "+5 Min",      extend_break)
    obs.obs_properties_add_button(props, "btn_break_end",    "End Break",   end_break)

    -- subject switching
    obs.obs_properties_add_button(props, "btn_prev_subject", "< Prev Subject", prev_subject)
    obs.obs_properties_add_button(props, "btn_next_subject", "Next Subject >", next_subject)

    return props
end

function script_update(settings)
    study_minutes        = obs.obs_data_get_int(settings,    "study_minutes")
    break_minutes        = obs.obs_data_get_int(settings,    "break_minutes")
    manual_break_minutes = obs.obs_data_get_int(settings,    "manual_break_minutes")
    total_hours          = obs.obs_data_get_int(settings,    "total_hours")
    resume_hours         = obs.obs_data_get_int(settings,    "resume_hours")
    resume_minutes       = obs.obs_data_get_int(settings,    "resume_minutes")
    resume_sessions      = obs.obs_data_get_int(settings,    "resume_sessions")
    warning_secs         = obs.obs_data_get_int(settings,    "warning_secs")
    auto_cycle           = obs.obs_data_get_bool(settings,   "auto_cycle")
    show_subject         = obs.obs_data_get_bool(settings,   "show_subject")
    show_subject_pct     = obs.obs_data_get_bool(settings,   "show_subject_pct")
    show_total           = obs.obs_data_get_bool(settings,   "show_total")
    enable_blink         = obs.obs_data_get_bool(settings,   "enable_blink")
    enable_fade          = obs.obs_data_get_bool(settings,   "enable_fade")
    study_scene_name     = obs.obs_data_get_string(settings, "study_scene_name")
    break_scene_name     = obs.obs_data_get_string(settings, "break_scene_name")
    log_file_path        = obs.obs_data_get_string(settings, "log_file_path")
    alarm_source_name    = obs.obs_data_get_string(settings, "alarm_source_name")
    custom_break_name    = obs.obs_data_get_string(settings, "custom_break_name")
    if custom_break_name == "" then custom_break_name = "BREAK" end

    local new_str = obs.obs_data_get_string(settings, "custom_subjects")
    if new_str ~= custom_subjects_str then
        custom_subjects_str   = new_str
        subjects              = parse_subjects(custom_subjects_str)
        current_subject_index = 1
        subject_seconds       = {}
        for i = 1, #subjects do subject_seconds[i] = 0 end
    end

    local new_src = obs.obs_data_get_string(settings, "source_name")
    if new_src ~= source_name then
        source_name = new_src
        if source ~= nil then obs.obs_source_release(source); source = nil end
        if source_name ~= "" then source = obs.obs_get_source_by_name(source_name) end
    end

    total_seconds = total_hours * 3600
    update_text()
end

function script_unload()
    obs.timer_remove(tick)
    obs.timer_remove(animate)
    if source ~= nil then
        obs.obs_source_release(source)
        source = nil
    end
end
