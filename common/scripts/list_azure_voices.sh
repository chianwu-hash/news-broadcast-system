#!/usr/bin/env bash
set -a; source /home/vboxuser/news-broadcast-system/.env; set +a

curl -sS \
  "https://${AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/voices/list" \
  -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
| python3 -c "
import json, sys
voices = json.load(sys.stdin)
tw = [v for v in voices if 'zh-TW' in v.get('Locale', '')]
for v in tw:
    name   = v.get('ShortName', '')
    styles = v.get('StyleList', [])
    roles  = v.get('RolePlayList', [])
    print(name)
    if styles: print(f'  styles: {styles}')
    if roles:  print(f'  roles:  {roles}')
"
