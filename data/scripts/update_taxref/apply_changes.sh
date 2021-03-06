#!/bin/bash

. ../../../settings.ini

taxref_version="${1:-13}"

LOG_DIR="../../../var/log/updatetaxrefv${taxref_version}"
mkdir -p $LOG_DIR


# Création fonction de dépendances des vues
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f ../../generic_drop_and_restore_deps_views.sql  &> $LOG_DIR/apply_changes.log

echo "Detection des changements"

file_name="scripts/2.1_taxref_changes_corrections_pre_detections.sql"
if test -e "$file_name";then
    echo "  Corrections prédétection"
    export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f $file_name &>> $LOG_DIR/apply_changes.log
fi
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f scripts/1.2_taxref_changes_detections_cas_actions.sql &>> $LOG_DIR/apply_changes.log

countconflicts=`export PGPASSWORD=$user_pg_pass;psql -X -A -h $db_host -U $user_pg -d $db_name -t -c "SELECT count(*) FROM tmp_taxref_changes.comp_grap WHERE action ilike '%Conflict%';"`

if [ $countconflicts -gt 0 ]
then
    echo "Il y a $countconflicts conflits non résolus qui empechent la mise à jour de taxref"
    sudo -u postgres -s psql -d $db_name  -f scripts/1.3_taxref_changes_detections_export.sql &>> $LOG_DIR/apply_changes.log
    exit;
fi

export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f scripts/2.0_detect_data_with_missing_cd_nom.sql &>> $LOG_DIR/apply_changes.log

countfloatingcd_nom=`export PGPASSWORD=$user_pg_pass;psql -X -A -h $db_host -U $user_pg -d $db_name -t -c "SELECT count(*) FROM tmp_taxref_changes.dps_fk_cd_nom WHERE NOT table_name IN ('taxonomie.bib_noms', 'taxonomie.taxref_protection_especes');"`

if [ $countfloatingcd_nom -gt 0 ]
then
    echo "Il y a $countfloatingcd_nom données ayant un cd_nom qui a disparu de taxref"
    echo "Plus de détail dans le fichier /tmp/liste_donnees_cd_nom_manquant.csv"
    sudo -n -u postgres -s psql -d $db_name -c "COPY tmp_taxref_changes.dps_fk_cd_nom TO '/tmp/liste_donnees_cd_nom_manquant.csv' DELIMITER ',' CSV HEADER;" &>> $LOG_DIR/apply_changes.log
    exit;
fi

file_name="scripts/2.2_taxref_changes_corrections_post_detections.sql"
if test -e "$file_name";then
    echo "  Corrections postdétection"
    export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f $file_name &>> $LOG_DIR/apply_changes.log
fi

echo "Detection conflits synthese si elle existe"


sudo -u postgres -s psql -d $db_name  -f scripts/1.3_taxref_changes_detections_export.sql &>> $LOG_DIR/apply_changes.log
echo "Export des bilans réalisés dans tmp"



echo "Import taxref v${taxref_version}"
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f scripts/3.1_taxref_change_db_structure.sql &>> $LOG_DIR/apply_changes.log
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f scripts/3.2_alter_taxref_data.sql &>> $LOG_DIR/apply_changes.log


# TODO gestion des nouveaux status de protection
echo "Mise à jour des statuts de protections"
if [ ${taxref_version} -eq 13 ];
then
    sudo -u postgres -s psql -v MYPGUSER=$user_pg -d $db_name  -f scripts/4.1_stpr_import_data_v13_raw_data.sql &>> $LOG_DIR/apply_changes.log
    #TODO : spliter en deux fichiers un exécuté par postgres et l'autre par geonatadmin
else
   sudo -u postgres -s psql -d $db_name  -f scripts/4.1_stpr_import_data.sql &>> $LOG_DIR/apply_changes.log
fi


file_name="scripts/4.2_stpr_update_concerne_mon_territoire.sql"
if test -e "$file_name";then
    echo "  MAJ données concernant mon territoire"
    export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f $file_name &>> $LOG_DIR/apply_changes.log
fi
echo "  Mise à jour des statuts de protections réalisée"

file_name="scripts/4.3_restore_local_constraints.sql"
if test -e "$file_name";then
    echo "Restauration des contraintes de clés étrangères spécifiques à ma base"
    export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f $file_name &>> $LOG_DIR/apply_changes.log
fi
echo "  Restauration des contraintes de clés étrangères spécifiques à ma base réalisée"

echo "Mise à jour des vues matérialisées"
export PGPASSWORD=$user_pg_pass;psql -h $db_host -U $user_pg -d $db_name  -f ../../refresh_materialized_view.sql &>> $LOG_DIR/apply_changes.log
