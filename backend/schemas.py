from pydantic import BaseModel, EmailStr
from models import RoleEnum
from datetime import date

# Schéma pour l'inscription
class UtilisateurCreate(BaseModel):
    nom_user: str
    email: str
    mot_de_passe: str
    role: RoleEnum = RoleEnum.employe

# Schéma pour la réponse (on cache le mot de passe !)
class UtilisateurReponse(BaseModel):
    id: int
    nom_user: str
    email: str
    role: RoleEnum

    class Config:
        from_attributes = True

# Schéma pour la connexion
class ConnexionForm(BaseModel):
    email: str
    mot_de_passe: str


    # Schéma pour créer une note de frais
class NoteDeFraisCreate(BaseModel):
    description: str
    montant_ttc: float
    montant_tva: float
    date_depense: str  # Format DD/MM/YYYY
    url_justificatif: str  # L'URL reçue lors de l'upload
    mission_id: int | None = None  # Optionnel, si lié à une mission spécifique

# Schéma pour la réponse envoyée par l'API
class NoteDeFraisReponse(BaseModel):
    id: int
    description: str
    montant_ttc: float
    montant_tva: float
    date_depense: date
    statut: str
    url_justificatif: str
    utilisateur_id: int

    class Config:
        from_attributes = True