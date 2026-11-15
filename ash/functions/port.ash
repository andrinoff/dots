function port -d 'show what is listening on a port: port 8080'
    lsof -nP -iTCP:$argv[1] -sTCP:LISTEN
end
