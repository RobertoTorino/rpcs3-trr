#pragma once

#include <QDialog>

class QLineEdit;
class QPushButton;

class cheat_engine_dialog : public QDialog
{
	Q_OBJECT

public:
	explicit cheat_engine_dialog(const QString& path, QWidget* parent = nullptr);

	QString get_path() const;

protected:
	void accept() override;

private Q_SLOTS:
	void BrowseForCheatEngine();
	void UpdateSaveState();

private:
	QLineEdit* m_path_input = nullptr;
	QPushButton* m_save_button = nullptr;
};