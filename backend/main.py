import os
import uuid
import json
from datetime import datetime
from typing import Generator
from fastapi import FastAPI, Depends, HTTPException, Form, UploadFile, File, Header
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
import bcrypt
import requests
import base64
from google import genai
from google.genai import types

# Importez vos modèles depuis votre fichier models.py
from models import Base, Utilisateur, NoteDeFrais, Justificatif, StatutEnum

# Configuration SDK Gemini (assurez-vous d'avoir défini votre variable d'environnement GEMINI_API_KEY)
from google import genai
from google.genai import types

client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

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
    # Pour ce test, on récupère le premier utilisateur (ou adaptez selon votre logique JWT)
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

os.makedirs("statiques", exist_ok=True)
app.mount("/statiques", StaticFiles(directory="statiques"), name="statiques")


# ==========================================
# 3. ROUTES DE L'API
# ==========================================

@app.post("/login")
async def login(
    username: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db)
):
    user = db.query(Utilisateur).filter(Utilisateur.email == username).first()
    
    if not user:
        raise HTTPException(status_code=400, detail="Identifiants incorrects")
    
    password_bytes = password.encode('utf-8')
    stored_hash_bytes = user.mot_de_passe.encode('utf-8')

    try:
        is_valid = bcrypt.checkpw(password_bytes, stored_hash_bytes)
    except Exception:
        is_valid = False

    if not is_valid:
        raise HTTPException(status_code=400, detail="Identifiants incorrects")
    
    return {
        "access_token": "fake-jwt-token-pour-test",
        "token_type": "bearer",
        "role": user.role.value if hasattr(user.role, "value") else user.role
    }


@app.get("/notes/en-attente")
async def get_notes_en_attente(db: Session = Depends(get_db)):
    try:
        notes = db.query(NoteDeFrais).filter(NoteDeFrais.statut == StatutEnum.en_attente).all()
        
        result = []
        for note in notes:
            justificatif_url = note.justificatif.url_fichier if note.justificatif else None
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "statut": note.statut.value if hasattr(note.statut, "value") else note.statut,
                "justificatif_url": justificatif_url,
                "user_id": note.utilisateur_id
            })
        return result
    except Exception as e:
        print(f"🔥 Erreur récupération notes : {e}")
        raise HTTPException(status_code=500, detail=str(e))
@app.post("/notes/upload-justificatif")
async def upload_justificatif(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: Utilisateur = Depends(get_current_user_from_token)
):
    try:
        file_extension = os.path.splitext(file.filename)[1].lower()
        unique_filename = f"{uuid.uuid4()}{file_extension}"
        file_path = os.path.join("statiques", unique_filename)
        
        contents = await file.read()
        with open(file_path, "wb") as buffer:
            buffer.write(contents)
        
        justificatif_url = f"/statiques/{unique_filename}"

        montant_ttc = 0.0
        montant_tva = 0.0
        date_depense_str = ""
        titre = f"Note - {file.filename}"

        try:
            mime_type = "application/pdf" if file_extension == ".pdf" else "image/jpeg"
            if file_extension == ".png":
                mime_type = "image/png"

            file_base64 = base64.b64encode(contents).decode('utf-8')
            api_key = os.environ.get("GEMINI_API_KEY")

            # URL de l'API REST standard de Gemini
            url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
            
            payload = {
                "contents": [
                    {
                        "parts": [
                            {
                                "text": (
                                    "Analyse ce justificatif de note de frais (ticket, facture ou reçu).\n"
                                    "Extrais les informations suivantes sous un format JSON strict :\n"
                                    '- "montant_ttc" (un nombre float, ex: 45.90, ou 0.0 si introuvable)\n'
                                    '- "montant_tva" (un nombre float, ex: 5.50, ou 0.0 si introuvable)\n'
                                    '- "date_depense" (au format AAAA-MM-JJ, ou chaîne vide si introuvable)\n'
                                    '- "titre" (un court résumé ou nom du marchand, ex: "Restaurant Le Petit Bouchon")\n'
                                    "Réponds UNIQUEMENT avec le JSON brut, sans balises markdown."
                                )
                            },
                            {
                                "inline_data": {
                                    "mime_type": mime_type,
                                    "data": file_base64
                                }
                            }
                        ]
                    }
                ]
            }

            # Passage du jeton AQ. dans le header Authorization Bearer
            headers = {
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {api_key}'
            }
            
            resp = requests.post(url, json=payload, headers=headers)

            if resp.status_code == 200:
                resp_data = resp.json()
                response_text = resp_data['candidates'][0]['content']['parts'][0]['text'].strip()
                
                if response_text.startswith("```json"):
                    response_text = response_text[7:-3].strip()
                elif response_text.startswith("```"):
                    response_text = response_text[3:-3].strip()

                extracted_data = json.loads(response_text)
                montant_ttc = float(extracted_data.get("montant_ttc", 0.0))
                montant_tva = float(extracted_data.get("montant_tva", 0.0))
                date_depense_str = extracted_data.get("date_depense", "")
                if extracted_data.get("titre"):
                    titre = extracted_data.get("titre")
            else:
                print(f"⚠️ Erreur HTTP Gemini : {resp.status_code} - {resp.text}")

        except Exception as ai_error:
            import traceback
            print(f"⚠️ Erreur lors de l'analyse IA : {ai_error}")
            traceback.print_exc()

        try:
            date_depense = datetime.strptime(date_depense_str, "%Y-%m-%d").date() if date_depense_str else datetime.now().date()
        except ValueError:
            date_depense = datetime.now().date()

        # Enregistrement dans la base MySQL
        nouvelle_note = NoteDeFrais(
            titre=titre,
            montant_ttc=montant_ttc,
            montant_tva=montant_tva,
            devise="EUR",
            date_depense=date_depense,
            statut=StatutEnum.en_attente,
            utilisateur_id=current_user.id
        )
        db.add(nouvelle_note)
        db.commit()
        db.refresh(nouvelle_note)

        nouveau_justificatif = Justificatif(
            url_fichier=justificatif_url,
            note_de_frais_id=nouvelle_note.id
        )
        db.add(nouveau_justificatif)
        db.commit()

        return {
            "message": "Succès",
            "note_creee": {
                "id": nouvelle_note.id,
                "titre": nouvelle_note.titre,
                "montant_ttc": float(nouvelle_note.montant_ttc),
                "montant_tva": float(nouvelle_note.montant_tva),
                "date_depense": str(nouvelle_note.date_depense),
                "justificatif_url": justificatif_url
            }
        }

    except Exception as e:
        print(f"🔥 Erreur serveur upload : {e}")
        raise HTTPException(status_code=500, detail=str(e))