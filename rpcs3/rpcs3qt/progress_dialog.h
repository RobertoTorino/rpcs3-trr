#pragma once

#include <QProgressDialog>

#if defined(_WIN32) && defined(HAVE_QT_WINEXTRAS)
#include <QWinTaskbarProgress>
#include <QWinTaskbarButton>
#endif

class progress_dialog : public QProgressDialog
{
public:
	progress_dialog(const QString &windowTitle, const QString &labelText, const QString &cancelButtonText, int minimum, int maximum, bool delete_on_close, QWidget *parent = Q_NULLPTR, Qt::WindowFlags flags = Qt::WindowFlags());
	~progress_dialog();
	void SetValue(int progress);
	void SignalFailure();

private:
#if defined(_WIN32) && defined(HAVE_QT_WINEXTRAS)
	std::unique_ptr<QWinTaskbarButton> m_tb_button = nullptr;
	QWinTaskbarProgress* m_tb_progress = nullptr;
#elif HAVE_QTDBUS
	void UpdateProgress(int progress, bool disable = false);
#endif
};
