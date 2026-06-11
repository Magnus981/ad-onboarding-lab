# AD Onboarding Lab

Dette prosjektet viser hvordan Active Directory, PowerShell og Git kan brukes sammen for å automatisere og dokumentere brukeroppretting.

## Tema

- Windows Server 2022 og Active Directory
- PowerShell-script for brukeroppretting
- GitHub for versjonskontroll og dokumentasjon

## AD-miljø

Server: DC01  
Domene: lab.local  

OU-er:
- IT
- Students
- Teachers

Grupper:
- VG1
- VG2
- Teachers-VG1
- Teachers-VG2

## PowerShell

Scriptet kan kjøres i to moduser:

RequestOnly:
- Lagrer forespørsel
- Gjør ingen endringer i AD

CreateAD:
- Oppretter bruker i Active Directory
- Plasserer bruker i riktig OU
- Legger bruker i riktig gruppe

## Git

Git brukes til å holde oversikt over endringer i script og dokumentasjon.
Logger og testdata er holdt utenfor Git med .gitignore.