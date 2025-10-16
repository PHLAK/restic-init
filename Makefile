.PHONY: configuration systemd-units

initialize init: configuration systemd-units

check-dependencies check-deps: # Check for installed dependencies
	@pacman --query systemd restic || true

configuration config: # Install configuration files
	@mkdir --parents --verbose /etc/restic
	@install --backup --mode u+rw configuration/* --verbose /etc/restic

systemd-units units: # Install systemd unit files
	@install ---mode u+rw,go+r systemd-units/*.{service,timer} -verbose /etc/systemd/system/
