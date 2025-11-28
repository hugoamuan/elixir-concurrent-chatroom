import java.io.*;
import java.net.*;

/**
 * TCP Chat Client
 * Connects to Chat.ProxyServer and lets user type chat commands manually
 */

public class ChatClient {
    public static void main(String[] args) {

	// localhost:6666
        String host = "127.0.0.1";
        int port = 6666;

	if (args.length >= 1){
	    host = args[0];
	}

	if (args.length >= 2){
        	try {
		port = Integer.parseInt(args[1]);
	 	} catch (NumberFormatException e) {
			System.err.println("invalid port #");
		}
	}


	// setup network connection
        try (
	    // open connection to server
            Socket socket = new Socket(host, port); 
	    
	    // receive messages through this stream
            BufferedReader serverIn = new BufferedReader(
                new InputStreamReader(socket.getInputStream())
            );
	    // send messages through this stream
            PrintWriter serverOut = new PrintWriter(
                new OutputStreamWriter(socket.getOutputStream()), true
            );
	    // read user input
            BufferedReader userIn = new BufferedReader(
                new InputStreamReader(System.in)
            )
        ) {
            
            System.out.printf("Welcome to chat server %s:%d%n", host, port);

	    // background thread that prints msg received from the server
            Thread listenerThread = new Thread(() -> {
                try {
                    String serverMessage;
                    while ((serverMessage = serverIn.readLine()) != null) {
                        System.out.println(serverMessage);
                    }
                } catch (IOException e) {
                    System.out.println("Connection closed by server");
                }
            });

	    // exit automatically
            listenerThread.setDaemon(true);
            listenerThread.start();

	    // User Input Loop - main thread reads user commands
            String userInput;
            while (true) {
                // ✅ println → print (so prompt stays on same line)
                System.out.print("> ");
                userInput = userIn.readLine();

                if (userInput == null) {
                    break;
                }

                // Send user input to chat server
                serverOut.println(userInput);
            }

            System.out.println("Client terminated.");
        } catch (IOException e) {
            System.err.println("Error connecting to server: " + e.getMessage());
        }
    }
}

