#!/usr/bin/env python3
"""Refresh public Apple release metadata and bundled icons. No account credentials."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode, urlparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ARTIST = 1874045866
DEST = ROOT / 'Sources/LorisLabsKit/Resources/Portfolio'
PROOF = ROOT / 'Qualification/Engagement-20261015'

# Product descriptions, independent of changing store titles or promotional copy.
DESCRIPTIONS = {
    '6760238729': ('Your Frigate cameras and events', 'Vos caméras et événements Frigate'),
    '6760317319': ('Frigate cameras on Apple TV', 'Vos caméras Frigate sur Apple TV'),
    '6759068382': ('Clipboard across your devices', 'Votre presse-papiers entre vos appareils'),
    '6758631803': ('Typing practice and statistics', 'Entraînement et statistiques de frappe'),
    '6760702536': ('Explore and diagnose your network', 'Explorez et diagnostiquez votre réseau'),
    '6775280371': ('Identify and block unwanted calls', 'Identifiez et bloquez les appels indésirables'),
    '6786621361': ('Accessible communication with symbols', 'Communication accessible par pictogrammes'),
    '6760730731': ('DNS filtering for your devices', 'Filtrage DNS pour vos appareils'),
    '6808961058': ('Manage your passwords', 'Gérez vos mots de passe'),
    '6790085975': ('Keep track of your pet’s health', 'Suivez la santé de votre animal'),
    '6784847934': ('Manage your OPNsense firewall', 'Gérez votre pare-feu OPNsense'),
    '6761294590': ('Track aurora conditions', 'Suivez les conditions des aurores'),
    '6793450821': ('Understand food and nutrition', 'Comprenez votre alimentation'),
    '6774200791': ('Plan your wake-ups', 'Organisez vos réveils'),
    '6793258211': ('Your media and transfers', 'Vos médias et vos transferts'),
    '6773836908': ('Create and open archives on Mac', 'Créez et ouvrez des archives sur Mac'),
    '6793437300': ('Scan and organize your documents', 'Numérisez et organisez vos documents'),
    '6821354551': ('Your meetings at a glance', 'Vos réunions en un coup d’œil'),
    '6784692429': ('Organize your documents on Mac', 'Organisez vos documents sur Mac'),
    '6795820987': ('Clean copies of your files', 'Nettoyez des copies de vos fichiers'),
    '6789967529': ('A vault for your files and passwords', 'Un coffre pour vos fichiers et mots de passe'),
}


def fetch(url):
    result = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location',
                             '--proto', '=https', '--proto-redir', '=https', '--max-time', '30', url],
                            capture_output=True, check=True)
    return result.stdout


def lookup(country):
    url = 'https://itunes.apple.com/lookup?' + urlencode({'id': ARTIST, 'entity': 'software', 'limit': 200, 'country': country})
    data = json.loads(fetch(url))
    assert data['resultCount'] < 200, 'catalog may be truncated'
    return country, url, data['results']


def main():
    now = datetime.now(timezone.utc)
    stores = list(ThreadPoolExecutor(max_workers=2).map(lookup, ['fr', 'us']))
    rows = {}
    for country, _, items in stores:
        for item in items:
            if item.get('wrapperType') != 'software': continue
            assert item['artistId'] == ARTIST, 'unexpected developer'
            if datetime.fromisoformat(item['releaseDate'].replace('Z', '+00:00')) > now: continue
            app_id = str(item['trackId'])
            row = rows.setdefault(app_id, {'id': app_id, 'bundleIdentifier': item['bundleId'],
                'category': item['primaryGenreName'], 'releaseDate': item['releaseDate'],
                'kind': item['kind'], 'countries': [], 'names': {}, 'artwork': item['artworkUrl512']})
            assert row['bundleIdentifier'] == item['bundleId']
            row['countries'].append(country); row['names'][country] = item['trackName']
    assert set(rows) <= set(DESCRIPTIONS), 'new app needs reviewed FR/EN descriptions: ' + str(sorted(set(rows)-set(DESCRIPTIONS)))
    assert len(rows) >= 20, 'catalog unexpectedly shrank; review before writing'
    icons = {}

    def icon(row):
        parsed = urlparse(row['artwork'])
        assert parsed.scheme == 'https' and parsed.hostname.endswith('.mzstatic.com')
        data = fetch(row['artwork'])
        extension = 'jpg' if data[:3] == b'\xff\xd8\xff' else 'png' if data[:8] == b'\x89PNG\r\n\x1a\n' else None
        assert extension and 1024 <= len(data) <= 2 * 1024 * 1024, 'unexpected artwork: ' + row['id'] + ' ' + data[:8].hex()
        return row['id'], data, extension

    for app_id, data, extension in ThreadPoolExecutor(max_workers=4).map(icon, rows.values()):
        icons[app_id] = data
        rows[app_id]['iconFileName'] = 'app-' + app_id + '.' + extension
    DEST.mkdir(parents=True, exist_ok=True); PROOF.mkdir(parents=True, exist_ok=True)
    catalog = []
    for app_id, row in rows.items():
        english, french = DESCRIPTIONS[app_id]
        name = row['names'].get('us') or row['names']['fr']
        catalog.append({'name': name, 'bundleIdentifier': row['bundleIdentifier'], 'ascAppId': app_id,
            'tagline': english, 'taglineFrench': french, 'category': row['category'],
            'appStoreCountry': '', 'nameFrench': row['names'].get('fr', name)})
        (DEST / row['iconFileName']).write_bytes(icons[app_id])
    catalog.sort(key=lambda row: row['name'].casefold())
    (DEST / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    proof = {'verifiedAt': now.isoformat(), 'artistId': ARTIST, 'sources': [url for _, url, _ in stores],
        'apps': [{**row, 'artworkSHA256': hashlib.sha256(icons[app_id]).hexdigest(),
                  'artworkBytes': len(icons[app_id]), 'storeURL': 'https://apps.apple.com/app/id' + app_id}
                 for app_id, row in sorted(rows.items())]}
    (PROOF / 'APPLE-RELEASE-CATALOG.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'releasedApps': len(catalog), 'embeddedIconBytes': sum(map(len, icons.values())),
                      'countries': {country: sum(country in row['countries'] for row in rows.values()) for country in ['fr','us']}}))


if __name__ == '__main__': main()
