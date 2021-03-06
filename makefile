-include ./settings.ini

develop:
	@/bin/bash -c "source venv/bin/activate&&python server.py runserver"


prod:
	@/bin/bash -c "./gunicorn_start.sh&"

prod-stop:
	@kill `cat $(app_name).pid`&&echo "Terminé."


shell:
	@/bin/bash -c "source $(venv_dir)/bin/activate&&python server.py shell"

stop:
	@/bin/bash -c "sudo -s supervisorctl stop $(app_name)"
