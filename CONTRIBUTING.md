# Contributing to Legacy Gantt Chart

Contributions are welcome! We appreciate your help in making this package even better.

## Reporting Bugs and Requesting Features

If you find a bug or have a feature request, please open an issue on our [GitHub issue tracker](https://github.com/barneysspeedshop/legacy_gantt_chart/issues). We have templates to help you provide the necessary information.

## Contributing Code

If you want to contribute code, please feel free to fork the repository and submit a Pull Request.

## License Assignment

By submitting a Pull Request to this repository, you agree to assign the copyright of your contribution to the project maintainer (Patrick Legacy / Barney's Speed Shop). This ensures that the maintainer retains 100% title of the codebase and can continue to manage and license the project effectively.

### Code Style

To maintain code quality and consistency, please adhere to the following style guidelines. These are enforced to prevent common linter warnings.

-   **Avoid `withOpacity` and `withAlpha`**: These methods can lead to precision loss or are inconsistent with our project's style. Always use `withValues(alpha:)` with a double value from 0.0 to 1.0 instead.
    
    ```dart
    // Incorrect
    myColor.withOpacity(0.5); // Deprecated in this project
    myColor.withAlpha(128);
    
    // Correct
    myColor.withValues(alpha: 0.5); // Alpha is a double from 0.0 to 1.0
    ```

-   **Use Expression Bodies**: For functions or methods that contain only a single return statement, use an expression body (`=>`) instead of a block body (`{ ... }`).
    
    ```dart
    // Incorrect
    String sayHello() {
      return 'Hello!';
    }
    
    // Correct
    String sayHello() => 'Hello!';
    ```
