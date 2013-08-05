
all:
	mkdir -p ebin
	erlc -o ebin +debug_info src/*

shell:
	erl -pa ebin
   
clean:
	rm -f ebin/* 

