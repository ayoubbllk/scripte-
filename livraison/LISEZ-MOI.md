# 🏭 Application Contrôle Qualité — Guide d'installation

## Contenu du livrable

Ce dossier contient l'application **Contrôle Qualité** prête à être installée sur votre poste local.

---

## Prérequis

Avant de commencer, assurez-vous d'avoir installé :

| Logiciel         | Version minimum | Obligatoire ? | Téléchargement                                      |
|------------------|-----------------|---------------|-----------------------------------------------------|
| **Node.js**      | 20 LTS          | Oui           | https://nodejs.org/fr (choisir LTS)                 |
| **Docker Desktop** | 4.x           | Non           | https://www.docker.com/products/docker-desktop/      |

> **Note** : Docker Desktop n'est **plus obligatoire**. Le script d'installation détecte automatiquement la meilleure méthode pour MySQL :
> 1. **Docker** (si disponible et démarré)
> 2. **MySQL local** (si déjà installé sur la machine)
> 3. **MySQL portable** (téléchargé automatiquement, aucune installation requise)

---

## Installation (Windows)

### Méthode rapide (recommandée)

1. **Ouvrez PowerShell** en tant qu'administrateur  
   *(Clic droit sur le menu Démarrer → "Windows PowerShell (Admin)")*

2. **Naviguez vers ce dossier** :
   ```powershell
   cd "C:\chemin\vers\ce\dossier\controle-qualite"
   ```

3. **Autorisez l'exécution du script** (une seule fois) :
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

4. **Lancez l'installation** :
   ```powershell
   .\installer.ps1
   ```

5. **Attendez** que le script se termine. Il va :
   - Vérifier les prérequis (Node.js)
   - Détecter MySQL (Docker, local, ou téléchargement portable automatique)
   - Créer le fichier de configuration `.env`
   - Démarrer la base de données MySQL
   - Installer les dépendances du projet
   - Configurer la base de données
   - Injecter les données de démonstration

6. **Lancez l'application** :
   ```powershell
   npm run dev
   ```

7. **Ouvrez votre navigateur** à l'adresse : **http://localhost:3000**

---

## Comptes de démonstration

| Rôle        | Email                        | Mot de passe |
|-------------|------------------------------|--------------|
| **Admin**   | admin@entreprise.com         | Admin@2026   |
| **Contrôleur** | controleur@entreprise.com | Ctrl@2026    |
| **Contrôleur** | labo@entreprise.com       | Labo@2026    |

---

## Commandes utiles

| Action                          | Commande                                 |
|---------------------------------|------------------------------------------|
| Lancer l'application            | `npm run dev`                            |
| Arrêter l'application           | `Ctrl + C` dans le terminal              |
| Voir la base de données         | `npm run db:studio`                      |
| Arrêter MySQL (Docker)          | `docker compose down`                    |
| Relancer MySQL (Docker)         | `docker compose up -d db`                |
| Arrêter MySQL (portable)        | `Get-Process mysqld \| Stop-Process`     |
| Relancer MySQL (portable)       | `.\installer.ps1 -SkipSeed`              |
| Réinitialiser les données démo  | `npx prisma db seed`                     |

---

## Structure de l'application

```
controle-qualite/
├── src/                  ← Code source de l'application
├── prisma/               ← Schéma de base de données
├── docker/               ← Configuration MySQL
├── docker-compose.yml    ← Orchestration Docker
├── package.json          ← Dépendances du projet
├── installer.ps1         ← Script d'installation automatique
└── LISEZ-MOI.md          ← Ce fichier
```

---

## Déploiement Docker (production)

Pour un déploiement complet avec Docker (application + base de données) :

```powershell
docker compose up -d
```

L'application sera accessible sur **http://localhost:3000**

---

## Résolution de problèmes

### "Docker n'est pas démarré" ou "Docker non installé"
→ Ce n'est plus bloquant ! Le script détecte automatiquement MySQL local ou télécharge MySQL portable. Relancez simplement `.\installer.ps1`.

### "Le port 3307 est déjà utilisé"
→ Un autre MySQL tourne sur votre machine. Le script le détectera et l'utilisera automatiquement.

### "Le port 3000 est déjà utilisé"
→ Modifiez `APP_PORT` dans le fichier `.env` ou fermez l'application qui utilise le port 3000.

### "Erreur de connexion à la base de données"
→ Selon votre mode d'installation :
- **Docker** : Vérifiez que Docker est lancé avec `docker ps`
- **Local** : Vérifiez que le service MySQL est démarré
- **Portable** : Relancez `.\installer.ps1 -SkipSeed`

### Réinitialisation complète
```powershell
npx prisma db push --force-reset   # Recrée les tables
npx prisma db seed                 # Réinjecte les données
```

---

## Support

En cas de problème, contactez l'équipe de développement avec :
- Le message d'erreur exact
- Une capture d'écran du terminal
- La version de Node.js (`node -v`) et Docker (`docker --version`)
