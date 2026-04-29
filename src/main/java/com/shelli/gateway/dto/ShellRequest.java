package com.shelli.gateway.dto;

/**
ShellRequest is a record class that represents a request to execute a shell command.
 It contains a single field, prompt, which is a string representing the command to be executed.
 This class is used to encapsulate the data for a shell command request in a structured way, making it easier to handle and process within the application.
*/

public record ShellRequest(String prompt) {

}
