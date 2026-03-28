#!/usr/bin/env python3
"""
Complete the Swedish translation with remaining strings.
"""

import re

def get_remaining_translations():
    """Additional Swedish translations for remaining strings."""
    
    return {
        # Basic actions
        "add": "Lägg till",
        "copy": "Kopiera", 
        "copy_1": "Kopiera",
        "done": "Klar",
        "skip": "Hoppa över",
        "start": "Starta",
        "rename": "Byt namn...",
        "delete_bulkdeleteselectioncount": "Ta bort \\(bulkDeleteSelection.count)",
        "select_all": "Markera allt",
        "select_multiple": "Välj flera...",
        
        # Various Cancel buttons (keep consistent)
        "cancel_2": "Avbryt",
        "cancel_3": "Avbryt", 
        "cancel_4": "Avbryt",
        "cancel_5": "Avbryt",
        "cancel_6": "Avbryt",
        
        # Choose dialogs
        "choose_1": "Välj...",
        "choose_a_folder_containing_your_knowledge_base_doc": "Välj en mapp som innehåller dina kunskapsbasdokument (.md, .txt)",
        "choose_where_to_save_meeting_transcripts": "Välj var mötesTranskript ska sparas",
        "choose_an_image_to_insert_into_notes": "Välj en bild att infoga i anteckningar",
        
        # Status messages  
        "idle": "Overksam",
        "listening_for_meetings": "Lyssnar efter möten...",
        "waiting_for_conversation": "Väntar på konversation...",
        "recording_formattedtime": "Spelar in - \\(formattedTime)",
        "evaluating_1": "Utvärderar...",
        "generating_notes": "Genererar anteckningar...",
        "cleaning_up_transcript_completedtotal_sections": "Rensar transkript... \\(completed)/\\(total) avsnitt",
        "completedtotal_cleaning": "\\(completed)/\\(total) rensar...",
        
        # Notes and transcript actions
        "generate_notes_1": "Generera anteckningar",
        "generate_notes_2": "Generera anteckningar", 
        "clean_up": "Rensa",
        "clean_up_1": "Rensa",
        "clean_up_remaining_utterances": "Rensa kvarvarande yttranden",
        "copy_to_clipboard": "Kopiera till urklipp",
        "copy_transcript_to_clipboard": "Kopiera transkript till urklipp",
        "remove_filler_words_and_fix_punctuation": "Ta bort fyllnadsord och fixa interpunktion",
        "show_original": "Visa original",
        "resume_autoscroll": "Återuppta automatisk rullning",
        
        # Search and navigation
        "no_matches": "Inga träffar",
        "clear_search": "Rensa sökning",
        "choose_a_session_from_the_sidebar_to_view_or_gener": "Välj en session från sidofältet för att visa eller generera anteckningar.",
        "this_session_has_no_recorded_utterances": "Denna session har inga inspelade yttranden.",
        
        # Session info
        "sessionutterancecount_utterances": "\\(session.utteranceCount) yttranden",
        "controllerstatelivetranscriptcount": "(\\(controllerState.liveTranscript.count))",
        
        # Images and media
        "insert_image": "Infoga bild", 
        "insert_an_image_into_notes": "Infoga en bild i anteckningar",
        "from_clipboard": "Från urklipp",
        "from_fileu2026": "Från fil…",
        "capture_screenshot": "Ta skärmbild",
        "image_not_found": "Bild hittades inte",
        
        # Tags
        "tags": "Taggar",
        "edit_tags": "Redigera taggar...",
        "maximum_5_tags_per_session": "Högst 5 taggar per session",
        
        # Download and updates
        "download_now": "Hämta nu",
        "check_for_updates_1": "Sök efter uppdateringar…",
        
        # Menu items
        "show_openoats": "Visa OpenOats",
        "quit_openoats": "Avsluta OpenOats",
        "openoats_1": "OpenOats",
        
        # Consent and legal
        "recording_consent_notice": "Medgivande för inspelning",
        "i_agree": "Jag godkänner",
        "i_understand_and_accept_these_obligations": "Jag förstår och accepterar dessa skyldigheter",
        
        # Templates and prompts
        "summarize_this_transcript_into_structured_meeting_": "Sammanfatta detta transkript till strukturerade mötesanteckningar.",
        "click_to_regenerate_or_pick_a_different_template": "Klicka för att återgenerera, eller välj en annan mall",
        
        # Bullet and formatting
        "u2022": "•",
        
        # Long descriptions (keeping concise Swedish)
        "autodetected_sessions_stop_after_this_many_minutes": "Automatiskt upptäckta sessioner stoppar efter så här många minuters tystnad.",
        "automatically_removes_filler_words_and_fixes_punct": "Tar automatiskt bort fyllnadsord och fixar interpunktion medan du spelar in. Du kan alltid rensa tidigare transkript manuellt från anteckningsfönstret.",
        "retranscribes_audio_with_a_higherquality_model_aft": "Omtranskriberar ljud med en högkvalitetsmodell efter varje möte för bättre precision. Körs i bakgrunden.",
        "save_a_local_audio_file_m4a_alongside_each_transcr": "Spara en lokal ljudfil (.m4a) tillsammans med varje transkript. Ljud lämnar aldrig din enhet.",
        "reduces_duplicate_transcription_when_using_speaker": "Minskar dubblettTranskription när du använder högtalare och mikrofon samtidigt. För närvarande inaktiverad under inspelning eftersom det står i konflikt med systemljudfångst på macOS.",
        "uses_lseend_to_distinguish_different_speakers_on_s": "Använder LS-EEND för att urskilja olika talare på systemljud. Kräver en engångsmodellnedladdning (~50 MB).",
        "when_enabled_the_app_is_invisible_during_screen_sh": "När aktiverat är appen osynlig under skärmdelning och inspelning.",
        "when_disabled_the_transcript_panel_is_hidden_durin": "När inaktiverat döljs transkriptpanelen under möten. Transkription körs fortfarande i bakgrunden för förslag och anteckningar.",
        "when_enabled_openoats_monitors_microphone_activati": "När aktiverat övervakar OpenOats mikrofonaktivering för att upptäcka när en mötesapp startar ett samtal. Inget ljud fångas förrän du accepterar aviseringen.",
        "where_meeting_transcripts_are_saved_as_plain_text_": "Här sparas mötesTranskript som rena textfiler.",
        "optional_point_this_to_a_folder_of_notes_docs_or_r": "Valfritt. Peka detta på en mapp med anteckningar, dokument eller referensmaterial (.md, .txt). Under möten söker OpenOats i denna mapp för att visa relevant kontext och diskussionspunkter.",
        "suggestions_appear_when_the_conversation_reaches_a": "Förslag visas när konversationen når ett ögonblick där din kunskapsbas kan hjälpa.",
        "one_term_per_line_optional_aliases_openoats_open_o": "Ett begrepp per rad. Valfria alias: OpenOats: open oats",
        "instructions_for_how_the_ai_should_format_notes_fo": "Instruktioner för hur AI:n ska formatera anteckningar för denna mötestyp.",
        "print_detection_events_to_the_system_console_for_d": "Skriv ut detekteringshändelser till systemkonsolen för felsökning.",
        "openoats_watches_for_microphone_activation_by_meet": "OpenOats bevakar mikrofonaktivering av mötesappar (Zoom, Teams, FaceTime, etc.)",
        "only_activation_status_is_checked_no_audio_is_capt": "Endast aktiveringsstatus kontrolleras. Inget ljud fångas eller spelas in förrän du accepterar.",
        "when_a_meeting_is_detected_you_get_a_macos_notific": "När ett möte upptäcks får du en macOS-avisering för att börja transkribera.",
        
        # Delete confirmations
        "this_will_permanently_delete_the_transcript_and_an": "Detta kommer att permanent ta bort transkriptet och alla genererade anteckningar.",
        "this_will_permanently_delete_the_selected_transcri": "Detta kommer att permanent ta bort de valda transkripten och alla genererade anteckningar.",
    }

def update_swedish_file():
    """Update the Swedish file with remaining translations."""
    
    additional_translations = get_remaining_translations()
    
    # Read current Swedish file
    with open('OpenOats/sv.lproj/Localizable.strings', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Parse current translations
    current_translations = {}
    matches = re.findall(r'"([^"]+)"\s*=\s*"([^"]+)";', content)
    for key, value in matches:
        current_translations[key] = value
    
    # Update with additional translations
    current_translations.update(additional_translations)
    
    # Read English file to get structure and comments
    with open('OpenOats/en.lproj/Localizable.strings', 'r', encoding='utf-8') as f:
        english_content = f.read()
    
    lines = english_content.split('\n')
    swedish_lines = []
    
    for line in lines:
        if line.startswith('//'):
            # Preserve comments
            swedish_lines.append(line)
        elif '=' in line and line.endswith(';'):
            # Replace with Swedish translation
            match = re.match(r'"([^"]+)"\s*=\s*"([^"]+)";', line)
            if match:
                key = match.group(1)
                if key in current_translations:
                    swedish_value = current_translations[key]
                    # Escape quotes in the value
                    escaped_value = swedish_value.replace('"', '\\"')
                    swedish_lines.append(f'"{key}" = "{escaped_value}";')
                else:
                    # Keep original if no Swedish translation
                    swedish_lines.append(line)
            else:
                swedish_lines.append(line)
        else:
            # Empty lines and other content
            swedish_lines.append(line)
    
    # Write updated Swedish file
    with open('OpenOats/sv.lproj/Localizable.strings', 'w', encoding='utf-8') as f:
        f.write('\n'.join(swedish_lines))
    
    print(f"Added {len(additional_translations)} more Swedish translations")

if __name__ == '__main__':
    update_swedish_file()