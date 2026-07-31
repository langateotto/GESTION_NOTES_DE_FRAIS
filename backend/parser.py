import pdfplumber
import re

import pytesseract
from PIL import Image
import os

# 1. Indiquer le chemin de l'exécutable
pytesseract.pytesseract.tesseract_cmd = r"C:\Program Files\Tesseract-OCR\tesseract.exe"

# 2. LA LIGNE MAGIQUE : On force Windows et Tesseract à trouver le dossier des langues
os.environ["TESSDATA_PREFIX"] = r"C:\Program Files\Tesseract-OCR\tessdata"

def extraire_texte_pdf(chemin_pdf: str) -> str:
    """Ouvre le PDF et extrait tout le texte brut."""
    texte_complet = ""
    with pdfplumber.open(chemin_pdf) as pdf:
        for page in pdf.pages:
            texte_brut = page.extract_text()
            if texte_brut:
                texte_complet += texte_brut + "\n"
    return texte_complet

def extraire_texte_image(chemin_image: str) -> str:
    """Ouvre une image (JPG, PNG) et utilise Tesseract pour extraire le texte."""
    try:
        image = Image.open(chemin_image)
        texte_extrait = pytesseract.image_to_string(image, lang="fra", config="--psm 6")
        
        # Ce print DOIT s'afficher dans votre PowerShell
        print("\n================ TESSERACT REUSSITE ================")
        print(texte_extrait)
        print("====================================================\n")
        
        return texte_extrait
    except Exception as e:
        print(f"\n❌ ERREUR CRITIQUE TESSERACT OCR : {e}\n")
        return ""

def convertir_mois_en_chiffre(texte: str) -> str:
    """Remplace les mois en texte par leur équivalent numérique pour uniformiser."""
    mois = {
        "janvier": "01", "février": "02", "mars": "03", "avril": "04", 
        "mai": "05", "juin": "06", "juillet": "07", "août": "08", 
        "septembre": "09", "octobre": "10", "novembre": "11", "décembre": "12"
    }
    texte_minuscule = texte.lower()
    for nom_mois, num_mois in mois.items():
        if nom_mois in texte_minuscule:
            # Exemple: "03 mai 2026" -> "03/05/2026"
            regex_remplacement = rf"(\d{{2}})\s+{nom_mois}\s+(\d{{4}})"
            match = re.search(regex_remplacement, texte_minuscule)
            if match:
                return f"{match.group(1)}/{num_mois}/{match.group(2)}"
    return None
import re

def analyser_donnees_facture(texte: str) -> dict:
    """Analyse le texte brut (PDF ou OCR) pour extraire la date et les montants."""
    donnees = {"date_depense": None, "montant_ttc": 0.0, "montant_tva": 0.0}
    
    if not texte:
        return donnees

    # 1. RECHERCHE DE LA DATE (Ex: "Dimanche 03 mai 2026" ou "03/05/2026")
    match_date = re.search(r"\b(\d{2}/\d{2}/\d{4})\b", texte)
    if match_date:
        donnees["date_depense"] = match_date.group(1)
    else:
        # Secours : Date textuelle en français
        mois_les = r"(janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)"
        match_date_texte = re.search(r"\b(\d{1,2})\s+" + mois_les + r"\s+(\d{4})\b", texte, re.IGNORECASE)
        if match_date_texte:
            mois_dict = {
                "janvier": "01", "février": "02", "mars": "03", "avril": "04", 
                "mai": "05", "juin": "06", "juillet": "07", "août": "08", 
                "septembre": "09", "octobre": "10", "novembre": "11", "décembre": "12"
            }
            jour = match_date_texte.group(1).zfill(2)
            mois_nom = match_date_texte.group(2).lower()
            annee = match_date_texte.group(3)
            mois = mois_dict.get(mois_nom, "01")
            donnees["date_depense"] = f"{jour}/{mois}/{annee}"

    # 2. RECHERCHE DU MONTANT TTC (Boostée pour l'OCR)
    # On attrape tous les nombres suivis de €, eur, ou euros (ex: 5€, 20€, 19€, 25,00€)
    motifs_montants = re.findall(r"(\d+(?:[\.,]\d{2})?)\s*(?:€|eur|euros)", texte, re.IGNORECASE)
    
    if motifs_montants:
        montants_floats = []
        for m in motifs_montants:
            try:
                montants_floats.append(float(m.replace(",", ".")))
            except ValueError:
                continue
        
        if montants_floats:
            # Stratégie OCR de secours : on prend le montant maximum trouvé textuellement
            # Ici, cela devrait attraper 20.0 (en attendant d'améliorer la qualité de l'image)
            donnees["montant_ttc"] = max(montants_floats)

    # 3. RECHERCHE DE LA TVA
    match_tva = re.search(r"(?:tva|dont\s+tva).*?(\d+(?:[\.,]\d{2})?)", texte, re.IGNORECASE)
    if match_tva:
        try:
            donnees["montant_tva"] = float(match_tva.group(1).replace(",", "."))
        except ValueError:
            pass

    return donnees