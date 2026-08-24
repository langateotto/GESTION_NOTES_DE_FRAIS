import enum
from datetime import datetime
from sqlalchemy import Column, Integer, String, ForeignKey, Numeric, Date, DateTime, Enum, TEXT
from sqlalchemy.orm import relationship
from database import Base
from pydantic import BaseModel

# ==========================================
# ENUMS (Pour limiter les choix dans la BD)
# ==========================================

class RoleEnum(str, enum.Enum):
    employe = "employe"
    manager = "manager"
    comptable = "comptable"

class StatutEnum(str, enum.Enum):
    brouillon = "brouillon"
    en_attente = "en_attente"
    valide = "valide"
    rejete = "rejete"
    annule = "annule"  # Statut d'annulation par l'employé inclus ici


# ==========================================
# MODÈLES / TABLES MYSQL
# ==========================================

class Utilisateur(Base):
    __tablename__ = "utilisateurs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    nom_user = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    mot_de_passe = Column(String(255), nullable=False)
    role = Column(Enum(RoleEnum), default=RoleEnum.employe, nullable=False)

    # Relations
    missions = relationship("Mission", back_populates="employe")
    notes_de_frais = relationship("NoteDeFrais", back_populates="employe")


class Mission(Base):
    __tablename__ = "missions"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    nom = Column(String(150), nullable=False)  # Ex: "Salon Tech Paris"
    date_debut = Column(Date, nullable=False)
    date_fin = Column(Date, nullable=False)
    utilisateur_id = Column(Integer, ForeignKey("utilisateurs.id", ondelete="CASCADE"), nullable=False)

    # Relations
    employe = relationship("Utilisateur", back_populates="missions")
    notes_de_frais = relationship("NoteDeFrais", back_populates="mission")


class NoteDeFrais(Base):
    __tablename__ = "notes_de_frais"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    titre = Column(String(150), nullable=False)
    montant_ttc = Column(Numeric(10, 2), nullable=False)
    montant_tva = Column(Numeric(10, 2), nullable=False)
    devise = Column(String(10), default="EUR", nullable=False)
    date_depense = Column(Date, nullable=False)
    statut = Column(Enum(StatutEnum), default=StatutEnum.en_attente, nullable=False)
    motif_rejet = Column(TEXT, nullable=True)
    
    date_soumission = Column(DateTime, default=datetime.now, nullable=False)
    
    utilisateur_id = Column(Integer, ForeignKey("utilisateurs.id", ondelete="CASCADE"), nullable=False)
    mission_id = Column(Integer, ForeignKey("missions.id", ondelete="SET NULL"), nullable=True)

    # Relations
    employe = relationship("Utilisateur", back_populates="notes_de_frais")
    mission = relationship("Mission", back_populates="notes_de_frais")
    justificatifs = relationship(
        "Justificatif", 
        back_populates="note_de_frais", 
        cascade="all, delete-orphan", 
        passive_deletes=True
    )

class Justificatif(Base):
    __tablename__ = "justificatifs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    url_fichier = Column(String(255), nullable=False)
    note_de_frais_id = Column(Integer, ForeignKey("notes_de_frais.id", ondelete="CASCADE"), nullable=False)

    note_de_frais = relationship("NoteDeFrais", back_populates="justificatifs")

class UserRegister(BaseModel):
    email: str
    password: str
    nom_user: str
    role: str = "employe"