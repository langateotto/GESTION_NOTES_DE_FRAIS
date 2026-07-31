from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
import jwt

from security import SECRET_KEY, ALGORITHM

# On ajoute le slash "/" pour être certain que Swagger trouve l'URL absolue
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/login")

def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token de connexion invalide ou expiré.",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        # Décodage du token
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        
        # Récupération de l'ID utilisateur depuis le "sub"
        user_id_str = payload.get("sub")
        if user_id_str is None:
            print("❌ Validation Échouée : Le champ 'sub' est absent du token payload.")
            raise credentials_exception
            
        return int(user_id_str)  # On s'assure de renvoyer un entier pour la BDD
        
    except Exception as e:
        # 🔥 ANALYSE DE L'ERREUR : Ceci va écrire la vraie raison du 401 dans votre terminal !
        print("\n🔒 [AUTH ERROR] Impossible de décoder le token JWT :")
        print(f"👉 Raison : {str(e)}")
        print(f"👉 Token reçu : {token[:15]}...\n")
        raise credentials_exception