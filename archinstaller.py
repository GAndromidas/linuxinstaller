#!/usr/bin/env python3
import sys
import os
import subprocess
from pathlib import Path
from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                            QHBoxLayout, QRadioButton, QPushButton, QTextEdit, 
                            QProgressBar, QLabel, QGroupBox, QButtonGroup,
                            QMessageBox, QFrame)
from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtGui import QFont, QTextCursor, QPalette, QColor, QPixmap, QPainter, QPen

class ArchLogo(QFrame):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumHeight(150)
        self.setMaximumHeight(150)
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        
        # Set colors
        arch_blue = QColor("#1793D1")
        painter.setPen(QPen(arch_blue, 2, Qt.PenStyle.SolidLine))
        
        # Draw Arch logo
        center_x = self.width() // 2
        center_y = self.height() // 2
        size = min(self.width(), self.height()) // 2
        
        # Draw the main triangle
        painter.drawLine(center_x, center_y - size//2, 
                        center_x - size//2, center_y + size//2)
        painter.drawLine(center_x, center_y - size//2,
                        center_x + size//2, center_y + size//2)
        painter.drawLine(center_x - size//2, center_y + size//2,
                        center_x + size//2, center_y + size//2)
        
        # Draw the inner triangle
        inner_size = size // 2
        painter.drawLine(center_x, center_y - inner_size//2,
                        center_x - inner_size//2, center_y + inner_size//2)
        painter.drawLine(center_x, center_y - inner_size//2,
                        center_x + inner_size//2, center_y + inner_size//2)
        painter.drawLine(center_x - inner_size//2, center_y + inner_size//2,
                        center_x + inner_size//2, center_y + inner_size//2)

class InstallerThread(QThread):
    output_received = pyqtSignal(str)
    progress_updated = pyqtSignal(int, str)
    finished = pyqtSignal(int)

    def __init__(self, install_mode):
        super().__init__()
        self.install_mode = install_mode
        self.total_steps = 20  # Total number of installation steps
        self.current_step = 0

    def run(self):
        script_dir = Path(__file__).parent
        try:
            process = subprocess.Popen(
                [f"{script_dir}/install.sh"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                env={**os.environ, "INSTALL_MODE": self.install_mode}
            )

            for line in process.stdout:
                line = line.strip()
                self.output_received.emit(line)
                
                # Track progress based on step markers
                if "[1]" in line:
                    self.current_step = 1
                    self.progress_updated.emit(1, "Checking prerequisites")
                elif "[2]" in line:
                    self.current_step = 2
                    self.progress_updated.emit(2, "Installing helper utilities")
                elif "[3]" in line:
                    self.current_step = 3
                    self.progress_updated.emit(3, "Configuring Pacman")
                elif "[4]" in line:
                    self.current_step = 4
                    self.progress_updated.emit(4, "Updating system")
                elif "[5]" in line:
                    self.current_step = 5
                    self.progress_updated.emit(5, "Setting up sudo")
                elif "[6]" in line:
                    self.current_step = 6
                    self.progress_updated.emit(6, "Installing CPU microcode")
                elif "[7]" in line:
                    self.current_step = 7
                    self.progress_updated.emit(7, "Installing kernel headers")
                elif "[8]" in line:
                    self.current_step = 8
                    self.progress_updated.emit(8, "Generating locales")
                elif "[9]" in line:
                    self.current_step = 9
                    self.progress_updated.emit(9, "Setting up ZSH")
                elif "[10]" in line:
                    self.current_step = 10
                    self.progress_updated.emit(10, "Installing Starship")
                elif "[11]" in line:
                    self.current_step = 11
                    self.progress_updated.emit(11, "Running custom scripts")
                elif "[12]" in line:
                    self.current_step = 12
                    self.progress_updated.emit(12, "Configuring boot")
                elif "[13]" in line:
                    self.current_step = 13
                    self.progress_updated.emit(13, "Setting up Fastfetch")
                elif "[14]" in line:
                    self.current_step = 14
                    self.progress_updated.emit(14, "Configuring firewall")
                elif "[15]" in line:
                    self.current_step = 15
                    self.progress_updated.emit(15, "Installing GPU drivers")
                elif "[16]" in line:
                    self.current_step = 16
                    self.progress_updated.emit(16, "Setting up maintenance")
                elif "[17]" in line:
                    self.current_step = 17
                    self.progress_updated.emit(17, "Cleaning up")
                elif "[18]" in line:
                    self.current_step = 18
                    self.progress_updated.emit(18, "Printing summary")
                elif "[19]" in line:
                    self.current_step = 19
                    self.progress_updated.emit(19, "Finalizing installation")

            process.wait()
            self.finished.emit(process.returncode)
        except Exception as e:
            self.output_received.emit(f"Error: {str(e)}")
            self.finished.emit(1)

class ArchInstallerGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Arch Linux Installer")
        self.setMinimumSize(800, 600)
        
        # Set dark theme colors
        self.setStyleSheet("""
            QMainWindow {
                background-color: #2b2b2b;
            }
            QWidget {
                background-color: #2b2b2b;
                color: #ffffff;
            }
            QGroupBox {
                border: 1px solid #3d3d3d;
                border-radius: 5px;
                margin-top: 1ex;
                font-weight: bold;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 3px 0 3px;
            }
            QRadioButton {
                color: #ffffff;
            }
            QPushButton {
                background-color: #1793D1;
                color: white;
                border: none;
                padding: 5px 15px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #1a9ee0;
            }
            QPushButton:disabled {
                background-color: #424242;
            }
            QTextEdit {
                background-color: #1e1e1e;
                color: #ffffff;
                border: 1px solid #3d3d3d;
                border-radius: 3px;
            }
            QProgressBar {
                border: 1px solid #3d3d3d;
                border-radius: 3px;
                text-align: center;
            }
            QProgressBar::chunk {
                background-color: #1793D1;
            }
            QLabel {
                color: #ffffff;
            }
        """)

        # Create central widget and main layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(10)
        main_layout.setContentsMargins(20, 20, 20, 20)

        # Arch Logo
        self.arch_logo = ArchLogo()
        main_layout.addWidget(self.arch_logo)

        # Title
        title_label = QLabel("Arch Linux Installer")
        title_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #1793D1;")
        main_layout.addWidget(title_label)

        # Installation Mode Group
        mode_group = QGroupBox("Installation Mode")
        mode_layout = QVBoxLayout()
        
        self.mode_group = QButtonGroup()
        self.default_radio = QRadioButton("Default (Full setup)")
        self.minimal_radio = QRadioButton("Minimal (Core utilities only)")
        self.default_radio.setChecked(True)
        
        self.mode_group.addButton(self.default_radio)
        self.mode_group.addButton(self.minimal_radio)
        
        mode_layout.addWidget(self.default_radio)
        mode_layout.addWidget(self.minimal_radio)
        mode_group.setLayout(mode_layout)
        main_layout.addWidget(mode_group)

        # Progress Information
        progress_group = QGroupBox("Installation Progress")
        progress_layout = QVBoxLayout()
        
        self.progress_label = QLabel("Ready to start installation")
        self.progress_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        progress_layout.addWidget(self.progress_label)
        
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 19)  # 19 steps total
        self.progress_bar.setValue(0)
        progress_layout.addWidget(self.progress_bar)
        
        progress_group.setLayout(progress_layout)
        main_layout.addWidget(progress_group)

        # Output Area
        output_group = QGroupBox("Installation Log")
        output_layout = QVBoxLayout()
        
        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setFont(QFont("Consolas", 10))
        output_layout.addWidget(self.output_text)
        
        output_group.setLayout(output_layout)
        main_layout.addWidget(output_group)

        # Buttons
        button_layout = QHBoxLayout()
        
        self.start_button = QPushButton("Start Installation")
        self.start_button.clicked.connect(self.start_installation)
        
        self.exit_button = QPushButton("Exit")
        self.exit_button.clicked.connect(self.close)
        
        button_layout.addWidget(self.start_button)
        button_layout.addWidget(self.exit_button)
        main_layout.addLayout(button_layout)

        # Initialize installer thread
        self.installer_thread = None

    def append_output(self, text):
        self.output_text.append(text)
        self.output_text.moveCursor(QTextCursor.MoveOperation.End)

    def update_progress(self, step, description):
        self.progress_bar.setValue(step)
        self.progress_label.setText(description)

    def start_installation(self):
        # Check if running as root
        if os.geteuid() == 0:
            QMessageBox.critical(self, "Error", "Do not run this script as root. Please run as a regular user with sudo privileges.")
            return

        # Check if pacman is available
        if not os.path.exists("/usr/bin/pacman"):
            QMessageBox.critical(self, "Error", "This script is intended for Arch Linux systems with pacman.")
            return

        self.start_button.setEnabled(False)
        
        # Get selected mode
        install_mode = "default" if self.default_radio.isChecked() else "minimal"
        
        # Create and start installer thread
        self.installer_thread = InstallerThread(install_mode)
        self.installer_thread.output_received.connect(self.append_output)
        self.installer_thread.progress_updated.connect(self.update_progress)
        self.installer_thread.finished.connect(self.installation_finished)
        self.installer_thread.start()

    def installation_finished(self, return_code):
        self.start_button.setEnabled(True)
        
        if return_code == 0:
            self.append_output("\nInstallation completed successfully!")
            QMessageBox.information(self, "Success", "Installation completed successfully!")
        else:
            self.append_output("\nInstallation failed!")
            QMessageBox.critical(self, "Error", "Installation failed! Check the output for details.")

    def closeEvent(self, event):
        if self.installer_thread and self.installer_thread.isRunning():
            reply = QMessageBox.question(
                self, 'Confirm Exit',
                "Installation is in progress. Are you sure you want to exit?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )
            
            if reply == QMessageBox.StandardButton.Yes:
                self.installer_thread.terminate()
                self.installer_thread.wait()
                event.accept()
            else:
                event.ignore()
        else:
            event.accept()

def main():
    app = QApplication(sys.argv)
    window = ArchInstallerGUI()
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
