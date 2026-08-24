import os 
import shutil
import uuid
import json
import bcrypt

from datetime import datetime
from typing import Generator, Optional
from fastapi import FastAPI, Depends, HTTPException, Form, UploadFile, File, Header, Request, BackgroundTasks, status
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from fastapi.security import OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel

# Vos modules locaux
from auth import get_current_user
from security import creer_token_acces, verifier_mot_de_passe
from models import Base, Utilisateur, NoteDeFrais, Justificatif, StatutEnum, UserRegister 

# Configuration SDK Gemini officiel
from google import genai
from google.genai import types
from pydantic import BaseModel

class PasswordReset(BaseModel):
    password: str # Ou new_password selon ce que Flutter envoie

class PasswordResetModel(BaseModel):
    password: Optional[str] = None
    mot_de_passe: Optional[str] = None

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Définissez le dossier où seront stockés les justificatifs
UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True) # Crée le dossier automatiquement s'il n'existe pas

# Clé API configurée directement ou via l'environnement
api_key = os.environ.get("GEMINI_API_KEY") 
client = genai.Client(api_key=api_key) if api_key else None

if not api_key:
    print("⚠️ Attention : Aucune clé GEMINI_API_KEY détectée. L'analyse automatique par IA est désactivée.")
else:
    print("✅ Clé GEMINI_API_KEY chargée avec succès.")

# ==========================================
# 1. CONNEXION MYSQL
# ==========================================
DATABASE_URL = "mysql+pymysql://root:garage@localhost:3307/gestion_ndf"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Dépendance pour récupérer l'utilisateur connecté via le token
def get_current_user_from_token(authorization: str = Header(None), db: Session = Depends(get_db)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Token manquant ou invalide")
    user = db.query(Utilisateur).first() 
    if not user:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable")
    return user

# ==========================================
# 2. CONFIGURATION APPLICATION
# ==========================================
app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 📂 Définition propre du dossier uploads avec un chemin absolu
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")

os.makedirs(UPLOAD_DIR, exist_ok=True)

# On monte le dossier sur la route "/uploads" pour correspondre à vos liens
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")
app.mount("/stockage_justificatifs", StaticFiles(directory="stockage_justificatifs"), name="stockage_justificatifs")


# Fonction utilitaire pour nettoyer les montants
def clean_float(value) -> float:
    if value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            cleaned = value.replace(",", ".").strip()
            for char in ["€", "$", "EUR", " "]:
                cleaned = cleaned.replace(char, "")
            return float(cleaned)
        except ValueError:
            return 0.0
    return 0.0


# ==========================================
# FONCTION D'ANALYSE IA EN ARRIÈRE-PLAN
# ==========================================
def executer_analyse_ia_arriere_plan(note_id: int, file_path: str, file_extension: str):
    """Exécute l'appel à Gemini avec des filtres de sécurité assouplis pour les factures."""
    if not client:
        return

    db = SessionLocal()
    try:
        if not os.path.exists(file_path):
            print(f"⚠️ Fichier introuvable sur le disque : {file_path}")
            return

        with open(file_path, "rb") as f:
            contents = f.read()

        mime_type = "application/pdf" if file_extension == ".pdf" else "image/jpeg"
        if file_extension == ".png":
            mime_type = "image/png"

        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=[
                types.Part.from_bytes(data=contents, mime_type=mime_type),
                (
                    "Analyse ce justificatif de frais (facture, ticket ou billet).\n"
                    "Extrais les informations sous un format JSON strict avec ces clés exactes :\n"
                    "- \"montant_ttc\" (float, ex: 45.90)\n"
                    "- \"montant_tva\" (float, ex: 7.50)\n"
                    "- \"date_depense\" (format YYYY-MM-DD)\n"
                    "- \"titre\" (string, nom du marchand ou description courte)\n\n"
                    "Réponds UNIQUEMENT avec le JSON valide, sans texte additionnel."
                ),
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.1,
                max_output_tokens=1000,
                safety_settings=[
                    types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold=types.HarmBlockThreshold.BLOCK_NONE),
                    types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold=types.HarmBlockThreshold.BLOCK_NONE),
                    types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_HARASSMENT, threshold=types.HarmBlockThreshold.BLOCK_NONE),
                    types.SafetySetting(category=types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold=types.HarmBlockThreshold.BLOCK_NONE),
                ]
            )
        )

        if not response or not hasattr(response, 'text') or not response.text:
            print("⚠️ Erreur : Réponse vide de Gemini.")
            return

        response_text = response.text.strip()
        if response_text.startswith("```json"):
            response_text = response_text[7:-3].strip()
        elif response_text.startswith("```"):
            response_text = response_text[3:-3].strip()

        extracted_data = json.loads(response_text)
        
        montant_ttc = clean_float(extracted_data.get("montant_ttc", 0.0))
        montant_tva = clean_float(extracted_data.get("montant_tva", 0.0))
        date_depense_str = extracted_data.get("date_depense", "")
        nouveau_titre = extracted_data.get("titre")

        note = db.query(NoteDeFrais).filter(NoteDeFrais.id == note_id).first()
        if note:
            note.montant_ttc = montant_ttc
            note.montant_tva = montant_tva
            if nouveau_titre:
                note.titre = nouveau_titre
            if date_depense_str:
                try:
                    note.date_depense = datetime.strptime(date_depense_str, "%Y-%m-%d").date()
                except ValueError:
                    pass
            db.commit()
            print(f"✅ Note {note_id} mise à jour avec succès par l'IA.")

    except json.JSONDecodeError as json_err:
        print(f"⚠️ Erreur de format JSON reçu de l'IA : {json_err}")
    except Exception as ai_error:
        print(f"⚠️ Erreur inattendue lors de l'analyse IA : {ai_error}")
    finally:
        db.close()


# ==========================================
# 3. ROUTES DE L'API
# ==========================================

@app.post("/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(Utilisateur).filter(Utilisateur.email == form_data.username).first()
    
    if not user or not verifier_mot_de_passe(form_data.password, user.mot_de_passe):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email ou mot de passe incorrect",
        )

    access_token = creer_token_acces(donnees={
        "sub": str(user.id), 
        "role": user.role
    })

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "role": user.role
    }

@app.get("/notes/en-attente")
async def get_notes_en_attente(db: Session = Depends(get_db)):
    try:
        notes = db.query(NoteDeFrais).filter(NoteDeFrais.statut == StatutEnum.en_attente).all()
        
        result = []
        for note in notes:
            justificatif_url = note.justificatifs[0].url_fichier if hasattr(note, 'justificatifs') and note.justificatifs else None
            
            employe_nom = "Employé"
            user_obj = getattr(note, 'employe', None) or getattr(note, 'utilisateur', None) or getattr(note, 'user', None)
            
            if user_obj:
                employe_nom = getattr(user_obj, 'nom_user', None) or getattr(user_obj, 'username', 'Employé')
            elif note.utilisateur_id:
                employe_nom = f"Utilisateur #{note.utilisateur_id}"
            
            val_statut = note.statut.value if hasattr(note.statut, "value") else note.statut
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "date_soumission": str(note.date_soumission) if hasattr(note, 'date_soumission') and note.date_soumission else None,
                "statut": val_statut,
                "justificatif_url": justificatif_url,
                "employe_nom": employe_nom,
                "user_id": note.utilisateur_id
            })
        return result
    except Exception as e:
        print(f"🔥 Erreur récupération notes : {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/notes/all")
async def get_all_expenses(
    statut: Optional[str] = None,
    db: Session = Depends(get_db)
):
    try:
        query = db.query(NoteDeFrais)
        
        if statut:
            try:
                enum_statut = StatutEnum(statut)
                query = query.filter(NoteDeFrais.statut == enum_statut)
            except ValueError:
                return []
            
        notes = query.all()
        
        result = []
        for note in notes:
            val_statut = note.statut.value if hasattr(note.statut, "value") else note.statut
            justificatif_url = note.justificatifs[0].url_fichier if hasattr(note, 'justificatifs') and note.justificatifs else None
            
            employe_nom = "Employé"
            for rel_name in ['employe', 'utilisateur']:
                if hasattr(note, rel_name) and getattr(note, rel_name):
                    rel_obj = getattr(note, rel_name)
                    if hasattr(rel_obj, 'nom_user') and rel_obj.nom_user:
                        employe_nom = rel_obj.nom_user
                        break
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "statut": val_statut,
                "justificatif_url": justificatif_url,
                "employe_nom": employe_nom,
                "user_id": note.utilisateur_id
            })
        return result
    except Exception as e:
        print(f"🔥 Erreur récupération de toutes les notes : {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.patch("/notes/{note_id}/statut")
async def update_note_status(
    note_id: int,
    statut: str = Form(...),
    motif_rejet: Optional[str] = Form(None),
    db: Session = Depends(get_db)
):
    try:
        note = db.query(NoteDeFrais).filter(NoteDeFrais.id == note_id).first()
        if not note:
            raise HTTPException(status_code=404, detail="Note de frais introuvable")
            
        statut_clean = statut.strip().lower()
        
        try:
            note.statut = StatutEnum(statut_clean)
        except ValueError:
            note.statut = statut_clean  

        db.commit()
        db.refresh(note)
        
        val_statut = note.statut.value if hasattr(note.statut, "value") else note.statut
        return {"message": "Statut mis à jour avec succès", "id": note.id, "nouveau_statut": val_statut}
    except Exception as e:
        db.rollback()
        print(f"🔥 Erreur mise à jour statut : {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/notes/mes-notes")
@app.get("/notes/my-notes")
async def get_mes_notes(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    try:
        user_id = current_user.id if hasattr(current_user, 'id') else current_user
        notes = db.query(NoteDeFrais).filter(NoteDeFrais.utilisateur_id == user_id).all()
        
        result = []
        for note in notes:
            justificatif_url = note.justificatifs[0].url_fichier if hasattr(note, 'justificatifs') and note.justificatifs else None
            val_statut = note.statut.value if hasattr(note.statut, "value") else note.statut
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "date_soumission": str(note.date_soumission) if hasattr(note, 'date_soumission') and note.date_soumission else None,
                "statut": val_statut,
                "justificatif_url": justificatif_url
            })
        return result
    except Exception as e:
        print(f"🔥 Erreur récupération mes notes : {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/notes/upload-justificatif")
async def upload_justificatif(file: UploadFile = File(...), db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    user_id = current_user.id if hasattr(current_user, 'id') else current_user
    file_extension = os.path.splitext(file.filename)[1]
    file_name = f"{uuid.uuid4()}{file_extension}"
    file_path = os.path.join(UPLOAD_DIR, file_name)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    justificatif_url = f"/uploads/{file_name}"

    montant_ttc = 0.0
    montant_tva = 0.0
    date_depense = datetime.now().date()
    titre = f"Note de frais - {file.filename}"

    if client:
        try:
            with open(file_path, "rb") as f:
                contents = f.read()

            mime_type = "application/pdf" if file_extension == ".pdf" else "image/jpeg"
            if file_extension == ".png":
                mime_type = "image/png"

            response = client.models.generate_content(
                model='gemini-3.6-flash',
                contents=[
                    types.Part.from_bytes(data=contents, mime_type=mime_type),
                    (
                        "Analyse ce justificatif de frais (facture, ticket ou billet).\n"
                        "Extrais les informations sous un format JSON strict avec ces clés exactes :\n"
                        "- \"montant_ttc\" (float, ex: 35.00)\n"
                        "- \"montant_tva\" (float, ex: 7.50)\n"
                        "- \"date_depense\" (format YYYY-MM-DD - la date d'achat figurant sur le ticket)\n"
                        "- \"titre\" (string, nom du marchand ou description courte)\n\n"
                        "Réponds UNIQUEMENT avec le JSON valide, sans texte additionnel."
                    ),
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    temperature=0.1,
                    max_output_tokens=1000
                )
            )

            if response and hasattr(response, 'text') and response.text:
                response_text = response.text.strip()
                if response_text.startswith("```json"):
                    response_text = response_text[7:-3].strip()
                elif response_text.startswith("```"):
                    response_text = response_text[3:-3].strip()

                extracted_data = json.loads(response_text)
                montant_ttc = clean_float(extracted_data.get("montant_ttc", 0.0))
                montant_tva = clean_float(extracted_data.get("montant_tva", 0.0))
                if extracted_data.get("titre"):
                    titre = extracted_data.get("titre")
                if extracted_data.get("date_depense"):
                    try:
                        date_depense = datetime.strptime(extracted_data.get("date_depense"), "%Y-%m-%d").date()
                    except ValueError:
                        pass
        except Exception as e:
            print(f"⚠️ Avertissement : L'analyse IA a échoué ({e}), création avec valeurs par défaut.")

    nouvelle_note = NoteDeFrais(
        utilisateur_id=user_id,
        titre=titre,
        montant_ttc=montant_ttc,
        montant_tva=montant_tva,
        devise="EUR",
        date_depense=date_depense,
        statut=StatutEnum.en_attente
    )
    db.add(nouvelle_note)
    db.commit()
    db.refresh(nouvelle_note)

    try:
        nouveau_justificatif = Justificatif(
            note_de_frais_id=nouvelle_note.id,
            url_fichier=justificatif_url
        )
        db.add(nouveau_justificatif)
        db.commit()
    except Exception as j_err:
        print(f"⚠️ Erreur insertion justificatif : {j_err}")

    date_soumission_str = str(nouvelle_note.date_soumission) if hasattr(nouvelle_note, 'date_soumission') and nouvelle_note.date_soumission else str(datetime.now())

    return {
        "message": "Fichier uploadé et enregistré avec succès",
        "note_creee": {
            "id": nouvelle_note.id,
            "titre": nouvelle_note.titre,
            "montant_ttc": float(nouvelle_note.montant_ttc),
            "montant_tva": float(nouvelle_note.montant_tva),
            "date_depense": str(nouvelle_note.date_depense),
            "date_soumission": date_soumission_str,
            "justificatif_url": justificatif_url
        }
    }


@app.post("/notes/")
async def create_note(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_from_token)
):
    try:
        user_id = current_user.id if hasattr(current_user, 'id') else current_user
        content_type = request.headers.get("content-type", "")
        
        if "application/json" in content_type:
            data = await request.json()
            titre = data.get("titre", "Note manuelle")
            montant_ttc = clean_float(data.get("montant_ttc", 0.0))
            date_str = data.get("date_depense", str(datetime.now().date()))
        else:
            form = await request.form()
            titre = form.get("titre", "Note manuelle")
            montant_ttc = clean_float(form.get("montant_ttc", 0.0))
            date_str = form.get("date_depense", str(datetime.now().date()))

        try:
            date_depense = datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            date_depense = datetime.now().date()

        nouvelle_note = NoteDeFrais(
            titre=titre,
            montant_ttc=montant_ttc,
            montant_tva=0.0,
            devise="EUR",
            date_depense=date_depense,
            statut=StatutEnum.en_attente,
            utilisateur_id=user_id
        )
        db.add(nouvelle_note)
        db.commit()
        db.refresh(nouvelle_note)

        return {"message": "Note créée avec succès", "id": nouvelle_note.id}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    

@app.put("/notes/{note_id}/annuler")
async def annuler_note_employe(
    note_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    try:
        user_id = current_user.id if hasattr(current_user, 'id') else current_user

        note = db.query(NoteDeFrais).filter(
            NoteDeFrais.id == note_id, 
            NoteDeFrais.utilisateur_id == user_id
        ).first()
        
        if not note:
            raise HTTPException(status_code=404, detail="Note de frais introuvable ou accès non autorisé.")
        
        if note.statut != StatutEnum.en_attente:
            raise HTTPException(
                status_code=400, 
                detail="Impossible d'annuler une note déjà traitée."
            )
        
        note.statut = StatutEnum.annule
        db.commit()
        
        return {"message": "Note de frais annulée avec succès."}
        
    except HTTPException as he:
        raise he
    except Exception as e:
        db.rollback()
        print(f"🔥 ERREUR CRITIQUE lors de l'annulation : {e}")
        raise HTTPException(status_code=500, detail=str(e))
    

@app.delete("/notes/{note_id}")
async def supprimer_note_comptable(
    note_id: int,
    db: Session = Depends(get_db)
):
    try:
        note = db.query(NoteDeFrais).filter(NoteDeFrais.id == note_id).first()
        if not note:
            raise HTTPException(status_code=404, detail="Note de frais introuvable.")
        
        if hasattr(note, 'justificatifs') and note.justificatifs:
            for justificatif in note.justificatifs:
                if justificatif.url_fichier:
                    filename = justificatif.url_fichier.split("/")[-1]
                    file_path = os.path.join(UPLOAD_DIR, filename)
                    if os.path.exists(file_path):
                        try:
                            os.remove(file_path)
                            print(f"🗑️ Fichier physique supprimé : {file_path}")
                        except Exception as ex:
                            print(f"⚠️ Impossible de supprimer le fichier physique : {ex}")

        db.delete(note)
        db.commit()
        
        return {"message": "Note de frais et justificatif supprimés avec succès."}
        
    except Exception as e:
        db.rollback()
        print(f"🔥 ERREUR lors de la suppression : {e}")
        raise HTTPException(status_code=500, detail=str(e))
    

@app.post("/register")
async def register(
    request: Request,
    db: Session = Depends(get_db)
):
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=422, detail="Format JSON invalide")

    email = data.get("email")
    password = data.get("password") or data.get("mot_de_passe")
    nom_user = data.get("nom_user") or data.get("nom")
    role = data.get("role", "employe")

    if not email or not password or not nom_user:
        raise HTTPException(
            status_code=422, 
            detail=f"Champs manquants. Reçu: {data}"
        )

    user_existant = db.query(Utilisateur).filter(Utilisateur.email == email).first()
    if user_existant:
        raise HTTPException(status_code=400, detail="Cet email est déjà utilisé")

    # --- CORRECTION DU HACHAGE ICI ---
    # Convertir le mot de passe en bytes, le tronquer à 72 octets max pour éviter l'erreur, et le hasher
    password_bytes = password.encode('utf-8')[:72]
    hashed_password = bcrypt.hashpw(password_bytes, bcrypt.gensalt()).decode('utf-8')
    # ---------------------------------

    nouveau_user = Utilisateur(
        email=email,
        mot_de_passe=hashed_password,
        nom_user=nom_user,
        role=role
    )

    db.add(nouveau_user)
    db.commit()
    db.refresh(nouveau_user)

    return {"message": "Utilisateur créé avec succès", "user_id": nouveau_user.id}

@app.get("/users")
async def get_all_users(db: Session = Depends(get_db)):
    # Récupère tous les utilisateurs de la base de données
    utilisateurs = db.query(Utilisateur).all()
    
    # Retourne la liste formatée sous forme de JSON pour l'application Flutter
    return [
        {
            "id": u.id,
            "nom_user": u.nom_user,
            "email": u.email,
            "role": u.role
        }
        for u in utilisateurs
    ]  

@app.put("/admin/users/{user_id}/password")
async def reset_user_password(
    user_id: int, 
    request: Request, # On récupère la requête brute
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    # 1. Vérification des rôles
    current_user_id = current_user.id if hasattr(current_user, 'id') else current_user
    admin_user = db.query(Utilisateur).filter(Utilisateur.id == current_user_id).first()
    if not admin_user or admin_user.role not in ['comptable', 'manager', 'admin']:
        raise HTTPException(status_code=403, detail="Accès non autorisé")

    # 2. Lecture sécurisée du corps JSON brut envoyé par Flutter
    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=422, detail="Le corps de la requête doit être un JSON valide.")

    # 3. Récupération du mot de passe peu importe le nom de la clé utilisée par Flutter
    plain_password = (
        data.get("password") or 
        data.get("mot_de_passe") or 
        data.get("new_password") or 
        data.get("nouveau_mot_de_passe")
    )

    if not plain_password:
        raise HTTPException(
            status_code=422, 
            detail=f"Clé 'password' ou 'mot_de_passe' introuvable dans le JSON reçu. Reçu : {data}"
        )

    # 4. Recherche de l'utilisateur cible
    user = db.query(Utilisateur).filter(Utilisateur.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
    
    # 5. Hachage et mise à jour
    password_bytes = plain_password.encode('utf-8')[:72]
    hashed_password = bcrypt.hashpw(password_bytes, bcrypt.gensalt()).decode('utf-8')
    
    user.mot_de_passe = hashed_password
    db.commit()
    
    return {"success": True, "message": "Mot de passe mis à jour avec succès"}