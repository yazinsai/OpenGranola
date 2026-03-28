#!/usr/bin/env python3
"""
Create Swedish translation following Språkrådet and l10n-review guidelines.
Uses du-tilltal, proper terminology, and natural Swedish expressions.
"""

import re

def parse_english_strings():
    """Parse the English Localizable.strings file."""
    strings = {}
    
    with open('OpenOats/en.lproj/Localizable.strings', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract key-value pairs
    matches = re.findall(r'"([^"]+)"\s*=\s*"([^"]+)";', content)
    for key, value in matches:
        strings[key] = value
    
    return strings

def translate_to_swedish():
    """Professional Swedish translations following Språkrådet guidelines."""
    
    translations = {
        # App and UI core terms
        "openoats": "OpenOats",  # Keep app name as-is
        "toggle_meeting": "Växla möte",
        "past_meetings": "Tidigare möten",
        "past_meetings_1": "Tidigare möten",
        "import_meeting_recording": "Importera mötesupptagning...",
        "import_meeting_recording_1": "Importera mötesupptagning",
        "github_repository": "GitHub-förråd...",
        
        # Recording and session management
        "recording_in_progress": "Inspelning pågår",
        "stop_recording_and_quit": "Stoppa inspelning och avsluta?",
        "stop_quit": "Stoppa och avsluta",
        "cancel": "Avbryt",
        "session_ended_u00b7_lastsessionutterancecount_utte": "Session avslutad · \\(lastSession.utteranceCount) yttranden",
        "view_notes": "Visa anteckningar",
        "generate_notes": "Generera anteckningar",
        "view_past_meeting_notes": "Visa anteckningar från tidigare möten",
        
        # Status and notifications
        "openoats_is_still_running": "OpenOats körs fortfarande",
        "meeting_detection_is_active_click_the_menu_bar_ico": "Mötesdetektering är aktiv. Klicka på menyfältsikonen för att komma åt kontroller.",
        "meeting_detected": "Möte upptäckt",
        "appname_is_using_your_microphone_tap_to_start_tran": "\\(appName) använder din mikrofon. Tryck för att börja transkribera.",
        "microphone_active": "Mikrofon aktiv",
        "a_meeting_may_be_in_progress_tap_to_start_transcri": "Ett möte kan pågå. Tryck för att börja transkribera.",
        "transcript_enhanced": "Transkript förbättrat",
        "batch_transcription_is_complete_your_meeting_trans": "Batchtranskription är klar. Ditt mötesTranskript har uppdaterats med högkvalitativ text.",
        
        # UI elements and controls  
        "check_for_updates": "Sök efter uppdateringar...",
        "transcript": "Transkript",
        "live_transcript": "Livetranskript",
        "evaluating": "Utvärderar...",
        "no_suggestions_yet": "Inga förslag än",
        "suggestions_appear_when_the_conversation_reaches": "Förslag visas när konversationen når ett ögonblick där din kunskapsbas kan hjälpa.",
        
        # Settings categories
        "meeting_notes": "Mötesanteckningar",
        "knowledge_base": "Kunskapsbas",
        "llm_provider": "LLM-leverantör",
        "embedding_provider": "Inbäddningsleverantör",
        "suggestions": "Förslag",
        "audio_input": "Ljudingång",
        "recording": "Inspelning",
        "transcription": "Transkription",
        "batch_refinement": "Batchförfining",
        "speaker_diarization": "Talaridentifiering",
        "privacy": "Integritet",
        "meeting_detection": "Mötesdetektering",
        "updates": "Uppdateringar",
        "meeting_templates": "Mötesmallar",
        
        # Settings descriptions
        "where_meeting_transcripts_are_saved_as_plain_text": "Här sparas mötesTranskript som rena textfiler.",
        "optional_point_this_to_a_folder_of_notes_docs_or": "Valfritt. Peka detta på en mapp med anteckningar, dokument eller referensmaterial (.md, .txt). Under möten söker OpenOats i denna mapp för att visa relevant kontext och diskussionspunkter.",
        "save_a_local_audio_file_m4a_alongside_each_transc": "Spara en lokal ljudfil (.m4a) tillsammans med varje transkript. Ljud lämnar aldrig din enhet.",
        "reduces_duplicate_transcription_when_using_speake": "Minskar dubblettTranskription när du använder högtalare och mikrofon samtidigt. För närvarande inaktiverad under inspelning eftersom det står i konflikt med systemljudfångst på macOS.",
        
        # Input and interaction
        "system_default": "Systemstandard",
        "choose": "Välj...",
        "clear": "Rensa",
        "not_set": "Inte inställt",
        "provider": "Leverantör",
        "model": "Modell",
        "verbosity": "Detaljnivå",
        "microphone": "Mikrofon",
        "save_audio_recording": "Spara ljudinspelning",
        "echo_cancellation": "Ekoborttagning",
        "show_live_transcript": "Visa livetranskript",
        "clean_up_transcript_during_recording": "Rensa transkript under inspelning",
        "enhance_transcript_after_meeting": "Förbättra transkript efter möte",
        "identify_multiple_remote_speakers": "Identifiera flera fjärrtalar",
        "hide_from_screen_sharing": "Dölj från skärmdelning",
        "auto_detect_meetings": "Upptäck möten automatiskt",
        "launch_at_login": "Starta vid inloggning",
        "automatically_check_for_updates": "Sök automatiskt efter uppdateringar",
        
        # Technical descriptions
        "when_disabled_the_transcript_panel_is_hidden_duri": "När inaktiverat döljs transkriptpanelen under möten. Transkription körs fortfarande i bakgrunden för förslag och anteckningar.",
        "automatically_removes_filler_words_and_fixes_punc": "Tar automatiskt bort fyllnadsord och fixar interpunktion medan du spelar in. Du kan alltid rensa tidigare transkript manuellt från anteckningsfönstret.",
        "re_transcribes_audio_with_a_higher_quality_model": "Omtranskriberar ljud med en högkvalitetsmodell efter varje möte för bättre precision. Körs i bakgrunden.",
        "uses_ls_eend_to_distinguish_different_speakers_on": "Använder LS-EEND för att urskilja olika talare på systemljud. Kräver en engångsmodellnedladdning (~50 MB).",
        "when_enabled_the_app_is_invisible_during_screen_s": "När aktiverat är appen osynlig under skärmdelning och inspelning.",
        "when_enabled_openoats_monitors_microphone_activat": "När aktiverat övervakar OpenOats mikrofonaktivering för att upptäcka när en mötesapp startar ett samtal. Inget ljud fångas förrän du accepterar aviseringen.",
        
        # Error and status messages
        "unable_to_check_for_updates": "Kan inte söka efter uppdateringar",
        "the_updater_failed_to_start_please_verify_you_have": "Uppdateraren kunde inte starta. Kontrollera att du har den senaste versionen av OpenOats och kontakta utvecklaren om problemet kvarstår.",
        
        # Consent and onboarding
        "openoats_needs_microphone_access_to_transcribe_me": "OpenOats behöver mikrofonåtkomst för att transkribera möten.",
        "grant_microphone_access": "Bevilja mikrofonåtkomst",
        "openoats_will_only_record_when_you_explicitly_sta": "OpenOats spelar endast in när du uttryckligen startar en session. Inget ljud lämnar din enhet utan ditt medgivande.",
        "understood": "Förstått",
        "i_understand_that_audio_will_be_processed_locally": "Jag förstår att ljud kommer att bearbetas lokalt och kan delas med AI-tjänster för transkription och förslag.",
        
        # Menu bar and overlay
        "start_recording": "Starta inspelning",
        "stop_recording": "Stoppa inspelning",
        "processing": "Bearbetar...",
        "show_main_window": "Visa huvudfönster",
        "check_for_updates": "Sök efter uppdateringar...",
        "quit": "Avsluta",
        "past_meetings_2": "Tidigare möten",
        "no_suggestions": "Inga förslag",
        
        # Transcript and content
        "open_transcript_in_separate_window": "Öppna transkript i separat fönster", 
        "copy_transcript": "Kopiera transkript",
        "transcript_1": "Transkript",
        "transcript_2": "Transkript",
        "importing_meeting_recording_progress": "Importerar mötesupptagning... \\(Int(progress * 100))%",
        "enhancing_transcript_progress": "Förbättrar transkript... \\(Int(progress * 100))%",
        "preparing_to_import": "Förbereder import...",
        "loading_batch_model": "Laddar batchmodell...",
        "meeting_recording_imported": "Mötesupptagning importerad",
        "transcript_enhanced_1": "Transkript förbättrat",
        "suggestions_1": "FÖRSLAG",
        
        # Template and advanced settings
        "new_template": "Ny mall",
        "cancel_1": "Avbryt",
        "save": "Spara",
        "reset": "Återställ",
        "name": "Namn",
        "icon": "Ikon",
        "notes_prompt": "Anteckningspromppt",
        "instructions_for_how_the_ai_should_format_notes_f": "Instruktioner för hur AI:n ska formatera anteckningar för denna mötestyp.",
        "custom_keywords": "Anpassade nyckelord",
        "one_term_per_line_optional_aliases_openoats_open": "Ett begrepp per rad. Valfria alias: OpenOats: open oats",
        "optional_boost_meeting_specific_jargon_names_and": "Valfritt. Förstärk mötesspecifik jargong, namn och produkttermer för Parakeet TDT v2/v3. Ange ett begrepp per rad, eller använd `Föredragen term: alias ett, alias två`.",
        "silence_timeout": "Tystnadstimeout",
        "min": "min",
        "auto_detected_sessions_stop_after_this_many_minu": "Automatiskt upptäckta sessioner stoppar efter så här många minuters tystnad.",
        "detection_log": "Detekteringslogg",
        "print_detection_events_to_the_system_console_for": "Skriv ut detekteringshändelser till systemkonsolen för felsökning.",
        "advanced_detection_settings": "Avancerade detekteringsinställningar",
        
        # Dialog explanations
        "how_meeting_detection_works": "Så fungerar mötesdetektering",
        "openoats_watches_for_microphone_activation_by_mee": "OpenOats bevakar mikrofonaktivering av mötesappar (Zoom, Teams, FaceTime, etc.)",
        "only_activation_status_is_checked_no_audio_is_cap": "Endast aktiveringsstatus kontrolleras. Inget ljud fångas eller spelas in förrän du accepterar.",
        "when_a_meeting_is_detected_you_get_a_macos_notifi": "När ett möte upptäcks får du en macOS-avisering för att börja transkribera.",
        "you_can_always_dismiss_the_notification_or_mark_i": "Du kan alltid avvisa aviseringen eller markera den som \"inte ett möte\".",
        "enable_detection": "Aktivera detektering",
    }
    
    return translations

def create_swedish_localizable():
    """Create the Swedish Localizable.strings file."""
    
    english_strings = parse_english_strings()
    swedish_translations = translate_to_swedish()
    
    # Read the English file to preserve comments and structure
    with open('OpenOats/en.lproj/Localizable.strings', 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    swedish_lines = []
    
    for line in lines:
        if line.startswith('//'):
            # Preserve comments as-is
            swedish_lines.append(line)
        elif '=' in line and line.endswith(';'):
            # Replace the translation
            match = re.match(r'"([^"]+)"\s*=\s*"([^"]+)";', line)
            if match:
                key = match.group(1)
                if key in swedish_translations:
                    swedish_value = swedish_translations[key]
                    # Escape quotes in the value
                    escaped_value = swedish_value.replace('"', '\\"')
                    swedish_lines.append(f'"{key}" = "{escaped_value}";')
                else:
                    # Keep original if no translation available
                    swedish_lines.append(line)
            else:
                swedish_lines.append(line)
        else:
            # Empty lines and other content
            swedish_lines.append(line)
    
    # Write Swedish file
    with open('OpenOats/sv.lproj/Localizable.strings', 'w', encoding='utf-8') as f:
        f.write('\n'.join(swedish_lines))
    
    # Report statistics
    translated_count = len(swedish_translations)
    total_count = len(english_strings)
    
    print(f"Swedish translation created!")
    print(f"Translated: {translated_count}/{total_count} strings")
    
    # Show any missing translations
    missing = set(english_strings.keys()) - set(swedish_translations.keys())
    if missing:
        print(f"\nStrings without Swedish translation ({len(missing)}):")
        for key in sorted(missing):
            print(f"  {key}: \"{english_strings[key]}\"")

if __name__ == '__main__':
    create_swedish_localizable()