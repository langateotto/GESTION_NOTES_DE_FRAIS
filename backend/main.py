import os
import uuid
import json
from datetime import datetime
from typing import Generator, Optional
from fastapi import FastAPI, Depends, HTTPException, Form, UploadFile, File, Header, Request
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
import bcrypt

# Importez vos modèles depuis votre fichier models.py
from models import Base, Utilisateur, NoteDeFrais, Justificatif, StatutEnum

# Configuration SDK Gemini officiel
from google import genai
from google.genai import types

# Clé API configurée directement ou via l'environnement
API_KEY = os.environ.get("GCP_API_KEY")

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

os.makedirs("statiques", exist_ok=True)
app.mount("/statiques", StaticFiles(directory="statiques"), name="statiques")


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
            employe_nom = f"{note.utilisateur.prenom} {note.utilisateur.nom}" if hasattr(note, 'utilisateur') and note.utilisateur else "Employé"
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "statut": note.statut.value if hasattr(note.statut, "value") else note.statut,
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
            query = query.filter(NoteDeFrais.statut == statut)
            
        notes = query.all()
        
        result = []
        for note in notes:
            justificatif_url = note.justificatif.url_fichier if note.justificatif else None
            employe_nom = f"{note.utilisateur.prenom} {note.utilisateur.nom}" if hasattr(note, 'utilisateur') and note.utilisateur else "Employé"
            
            result.append({
                "id": note.id,
                "titre": note.titre,
                "montant_ttc": float(note.montant_ttc),
                "montant_tva": float(note.montant_tva),
                "devise": note.devise,
                "date_depense": str(note.date_depense),
                "statut": note.statut.value if hasattr(note.statut, "value") else note.statut,
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
            
        note.statut = statut
        db.commit()
        return {"message": "Statut mis à jour avec succès", "id": note.id, "nouveau_statut": note.statut}
    except Exception as e:
        db.rollback()
        print(f"🔥 Erreur mise à jour statut : {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/notes/mes-notes")
@app.get("/notes/my-notes")
async def get_mes_notes(
    db: Session = Depends(get_db),
    current_user: Utilisateur = Depends(get_current_user_from_token)
):
    try:
        notes = db.query(NoteDeFrais).filter(NoteDeFrais.utilisateur_id == current_user.id).all()
        
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
                "justificatif_url": justificatif_url
            })
        return result
    except Exception as e:
        print(f"🔥 Erreur récupération mes notes : {e}")
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

        if client:
            try:
                mime_type = "application/pdf" if file_extension == ".pdf" else "image/jpeg"
                if file_extension == ".png":
                    mime_type = "image/png"

                response = client.models.generate_content(
                    model='gemini-3.6-flash', 
                    contents=[
                        types.Part.from_bytes(
                            data=contents,
                            mime_type=mime_type,
                        ),
                        (
                            "Tu es un expert comptable. Analyse ce document (facture, ticket de caisse ou billet de train type OUIGO).\n"
                            "Extrais les informations suivantes sous un format JSON strict :\n\n"
                            "- \"montant_ttc\" : Le montant TOTAL payé (cherche les mots clés 'TOTAL', 'TTC', 'NET A PAYER' ou 'Total voyageur'). Si absent, mets 0.0.\n"
                            "- \"montant_tva\" : Le montant total de la TVA. Si la TVA n'est pas explicitement écrite, mets 0.0.\n"
                            "- \"date_depense\" : La date de la dépense ou du voyage au format AAAA-MM-JJ (ex: 2026-05-03). Si introuvable, chaîne vide.\n"
                            "- \"titre\" : Le nom du marchand ou un court résumé du trajet/dépense (ex: 'OUIGO - Paris / Marseille', 'Restaurant Le Bouchon').\n\n"
                            "Réponds UNIQUEMENT avec un objet JSON valide, sans texte additionnel et sans blocs de code markdown."
                        ),
                    ],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json"
                    )
                )

                response_text = response.text.strip()
                
                if response_text.startswith("```json"):
                    response_text = response_text[7:-3].strip()
                elif response_text.startswith("```"):
                    response_text = response_text[3:-3].strip()

                print(f"🤖 Réponse brute de l'IA : {response_text}")

                extracted_data = json.loads(response_text)
                
                montant_ttc = clean_float(extracted_data.get("montant_ttc", 0.0))
                montant_tva = clean_float(extracted_data.get("montant_tva", 0.0))
                date_depense_str = extracted_data.get("date_depense", "")
                
                if extracted_data.get("titre"):
                    titre = extracted_data.get("titre")

            except Exception as ai_error:
                import traceback
                print(f"⚠️ Erreur lors de l'analyse IA : {ai_error}")
                traceback.print_exc()
        else:
            print("ℹ️ Analyse IA ignorée (aucune clé API configurée).")

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


@app.post("/notes/")
async def create_note(
    request: Request,
    db: Session = Depends(get_db),
    current_user: Utilisateur = Depends(get_current_user_from_token)
):
    """
    Route de secours universelle (gère formulaire ou JSON) pour éviter les erreurs 422 
    si Flutter tente d'envoyer des données directement ici.
    """
    try:
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
            utilisateur_id=current_user.id
        )
        db.add(nouvelle_note)
        db.commit()
        db.refresh(nouvelle_note)

        return {"message": "Note créée avec succès", "id": nouvelle_note.id}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))