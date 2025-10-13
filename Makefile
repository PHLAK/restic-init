.PHONY: configuration systemd-units

initialize init: configuration systemd-units

check-dependencies check-deps: # Check for installed dependencies
	@pacman --query systemd restic || true

configuration config: # Install configuration files
	@mkdir --parents --verbose /etc/restic
	@install --backup --verbose configuration/* /etc/restic

systemd-units units: # Install systemd unit files
	@install --backup --verbose systemd-units/*.{service,timer} /etc/systemd/system/
