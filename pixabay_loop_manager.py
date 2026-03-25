import os
import requests

# Récupération de la clé API depuis l'environnement
API_KEY = os.getenv('PIXABAY_API_KEY')

def fetch_top_loop(theme):
    url = "https://pixabay.com/api/videos/"
    
    # On construit le dictionnaire de paramètres basé sur ta doc
    params = {
        'key': API_KEY,
        'q': f"{theme} seamless loop",
        'lang': 'en',
        'orientation': 'horizontal', # Indispensable pour desktop
        'editors_choice': 'true',     # Qualité premium
        'safesearch': 'true',
        'order': 'popular',
        'per_page': 3                # On récupère les 3 meilleurs pour avoir du choix
    }

    response = requests.get(url, params=params)
    data = response.json()

    if data['totalHits'] > 0:
        # On prend la première vidéo des résultats
        video = data['hits'][0]
        # On récupère l'URL de la version large (souvent 4K ou HD)
        return video['videos']['large']['url']
    
    return None