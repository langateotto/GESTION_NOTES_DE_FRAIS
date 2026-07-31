from datetime import datetime, timedelta, timezone
import jwt
import bcrypt  # <-- On utilise directement la vraie bibliothèque standard

# Configuration JWT
SECRET_KEY = "SUPER_SECRET_KEY_POUR_LES_NOTES_DE_FRAIS_2026"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60


# ==============================================================================
# 1. GESTION DES MOTS DE PASSE (CORRIGÉE SANS PASSLIB)
# ==============================================================================

def hacher_mot_de_passe(mot_de_passe: str) -> str:
    """Transforme un mot de passe en texte brut en un hash sécurisé bcrypt."""
    # Convertit le texte brut en octets (bytes)
    mot_de_passe_bytes = mot_de_passe.encode('utf-8')
    
    # Génère le grain de sel (salt) et crée le hash
    sel = bcrypt.gensalt()
    hash_bytes = bcrypt.hashpw(mot_de_passe_bytes, sel)
    
    # Renvoie une chaîne de caractères lisible pour la stocker dans MySQL
    return hash_bytes.decode('utf-8')


def verifier_mot_de_passe(mot_de_passe_brut: str, mot_de_passe_hache: str) -> bool:
    """Vérifie si le mot de passe correspond au hash stocké."""
    try:
        # On convertit tout en octets (bytes) pour que bcrypt puisse comparer
        brut_bytes = mot_de_passe_brut.encode('utf-8')
        hache_bytes = mot_de_passe_hache.encode('utf-8')
        
        return bcrypt.checkpw(brut_bytes, hache_bytes)
    except Exception:
        return False


# ==============================================================================
# 2. GESTION DES TOKENS JWT
# ==============================================================================

def creer_token_acces(donnees: dict) -> str:
    """Génère un Token JWT signé pour l'utilisateur."""
    copie_donnees = donnees.copy()
    expiration = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    copie_donnees.update({"exp": expiration})
    return jwt.encode(copie_donnees, SECRET_KEY, algorithm=ALGORITHM)